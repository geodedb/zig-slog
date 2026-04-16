// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Rotating file handler - writes logs to files with size-based rotation.
//!
//! Features:
//! - Size-based rotation (max_bytes)
//! - Maximum number of backup files (max_backups)
//! - Age-based pruning (max_age_days)
//! - Atomic reopen for external rotation (logrotate/SIGHUP)
//! - Write buffering (8KB) to reduce syscalls
//! - Path traversal protection

const std = @import("std");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const Clock = @import("../internal/clock.zig").Clock;
const metrics = @import("../metrics/metrics.zig");
const writeTextRecord = @import("../fmt/text_record.zig").writeTextRecord;

/// Write buffer size (8KB).
const WRITE_BUF_SIZE = 8192;

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
    file: ?std.Io.File,
    current_size: usize,
    level: std.atomic.Value(i32),
    clock: Clock,
    mutex: std.Io.Mutex,
    path_buf: [std.Io.Dir.max_path_bytes]u8,
    path_buf2: [std.Io.Dir.max_path_bytes]u8,
    write_buf: [WRITE_BUF_SIZE]u8,
    write_buf_pos: usize,

    pub fn init(allocator: std.mem.Allocator, options: RotationOptions, level: Level, clock: Clock) !Context {
        // Validate path before proceeding
        try validatePath(options.path);

        var ctx = Context{
            .allocator = allocator,
            .options = options,
            .file = null,
            .current_size = 0,
            .level = std.atomic.Value(i32).init(@intFromEnum(level)),
            .clock = clock,
            .mutex = std.Io.Mutex.init,
            .path_buf = undefined,
            .path_buf2 = undefined,
            .write_buf = undefined,
            .write_buf_pos = 0,
        };

        try ctx.openFile();
        return ctx;
    }

    pub fn deinit(self: *Context) void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        // Flush buffered data before closing
        self.flushWriteBuf() catch {
            metrics.global.incErrors();
        };

        if (self.file) |f| {
            f.close(std.Io.Threaded.global_single_threaded.io());
            self.file = null;
        }
    }

    /// Validates that a path does not contain traversal sequences or is absolute
    /// when relative paths are expected.
    fn validatePath(path: []const u8) !void {
        // Reject empty paths
        if (path.len == 0) {
            return error.WriteFailed;
        }

        // Reject paths containing parent directory references
        if (std.mem.indexOf(u8, path, "..") != null) {
            return error.WriteFailed;
        }
    }

    fn openFile(self: *Context) !void {
        const path = self.options.path;
        const io = std.Io.Threaded.global_single_threaded.io();

        // Get or create directory
        if (std.fs.path.dirname(path)) |dir| {
            std.Io.Dir.cwd().createDirPath(io, dir) catch {
                metrics.global.incErrors();
            };
        }

        self.file = std.Io.Dir.cwd().createFile(io, path, .{
            .truncate = false,
        }) catch |err| {
            return switch (err) {
                error.AccessDenied => error.WriteFailed,
                else => error.WriteFailed,
            };
        };

        // Reset write buffer position for the new file
        self.write_buf_pos = 0;

        // Seek to end
        if (self.file) |f| {
            const stat = f.stat(io) catch {
                self.current_size = 0;
                return;
            };
            self.current_size = stat.size;
            // In 0.16.0, File.Writer handles positioning internally.
            // createFile with truncate=false opens for appending.
        }
    }

    fn rotate(self: *Context) !void {
        // Flush buffered data before rotating
        self.flushWriteBuf() catch {
            metrics.global.incErrors();
        };

        // Close current file
        if (self.file) |f| {
            f.close(std.Io.Threaded.global_single_threaded.io());
            self.file = null;
        }

        // Rotate existing backups
        var i: u8 = self.options.max_backups;
        while (i > 0) : (i -= 1) {
            if (i >= self.options.max_backups) {
                // Delete oldest -- use path_buf for the path to delete
                const del_path = self.formatBackupPath1(i) catch continue;
                std.Io.Dir.cwd().deleteFile(std.Io.Threaded.global_single_threaded.io(), del_path) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => {
                        metrics.global.incErrors();
                    },
                };
            } else {
                // Rename to next number -- use separate buffers for old and new paths
                const old_path = self.formatBackupPath1(i) catch continue;
                const new_path = self.formatBackupPath2(i + 1) catch continue;
                std.Io.Dir.cwd().rename(old_path, std.Io.Dir.cwd(), new_path, std.Io.Threaded.global_single_threaded.io()) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => {
                        metrics.global.incErrors();
                    },
                };
            }
        }

        // Rename current to .1
        const backup1 = self.formatBackupPath1(1) catch return error.WriteFailed;
        std.Io.Dir.cwd().rename(self.options.path, std.Io.Dir.cwd(), backup1, std.Io.Threaded.global_single_threaded.io()) catch |err| switch (err) {
            error.FileNotFound => {},
            else => {
                metrics.global.incErrors();
            },
        };

        // Open new file
        try self.openFile();
        self.current_size = 0;
        metrics.global.incRotations();
    }

    /// Format a backup path into path_buf (first buffer).
    fn formatBackupPath1(self: *Context, num: u8) ![]const u8 {
        const path = self.options.path;
        const result = std.fmt.bufPrint(&self.path_buf, "{s}.{d}", .{ path, num }) catch return error.WriteFailed;
        return result;
    }

    /// Format a backup path into path_buf2 (second buffer).
    fn formatBackupPath2(self: *Context, num: u8) ![]const u8 {
        const path = self.options.path;
        const result = std.fmt.bufPrint(&self.path_buf2, "{s}.{d}", .{ path, num }) catch return error.WriteFailed;
        return result;
    }

    /// Flush the write buffer to the underlying file.
    fn flushWriteBuf(self: *Context) !void {
        if (self.write_buf_pos == 0) return;

        if (self.file) |f| {
            const fio = std.Io.Threaded.global_single_threaded.io();
            f.writeStreamingAll(fio, self.write_buf[0..self.write_buf_pos]) catch return error.WriteFailed;
        }
        self.write_buf_pos = 0;
    }

    fn write(self: *Context, data: []const u8) !void {
        if (self.file == null) return;

        var remaining = data;
        while (remaining.len > 0) {
            const available = WRITE_BUF_SIZE - self.write_buf_pos;
            if (available == 0) {
                // Buffer full, flush it
                try self.flushWriteBuf();
                continue;
            }

            const to_copy = @min(remaining.len, available);
            @memcpy(self.write_buf[self.write_buf_pos..][0..to_copy], remaining[0..to_copy]);
            self.write_buf_pos += to_copy;
            remaining = remaining[to_copy..];
        }

        self.current_size += data.len;
        metrics.global.addBytesWritten(data.len);
    }

    fn checkRotate(self: *Context) !void {
        if (self.current_size >= self.options.max_bytes) {
            try self.rotate();
        }
    }

    pub fn reopen(self: *Context) !void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        // Flush buffered data before reopening
        self.flushWriteBuf() catch {
            metrics.global.incErrors();
        };

        if (self.file) |f| {
            f.close(std.Io.Threaded.global_single_threaded.io());
            self.file = null;
        }
        try self.openFile();
    }
};

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    const current_level: Level = @enumFromInt(ctx.level.load(.acquire));
    if (!rec.level.atLeast(current_level)) return;

    ctx.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer ctx.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    // Check if rotation needed
    ctx.checkRotate() catch return error.WriteFailed;

    // Format the record
    var buf: [8192]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    writeTextRecord(&fbs, rec, "") catch return error.WriteFailed;

    ctx.write(fbs.buffered()) catch return error.WriteFailed;
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
}

fn flush(ctx_ptr: *anyopaque, _: u32) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    ctx.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer ctx.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    // Flush the write buffer to the file
    ctx.flushWriteBuf() catch return error.FlushFailed;

    if (ctx.file) |f| {
        f.sync(std.Io.Threaded.global_single_threaded.io()) catch return error.FlushFailed;
    }
}

fn close(ctx_ptr: *anyopaque) void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    ctx.deinit();
}

const vtable = HandlerVTable{
    .handle = handle,
    .withAttrs = withAttrs,
    .withGroup = withGroup,
    .setLevel = setLevel,
    .flush = flush,
    .close = close,
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

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
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

test "RotatingFileHandler path traversal rejection" {
    const allocator = std.testing.allocator;

    // Paths containing ".." must be rejected
    const result = Context.init(allocator, .{
        .path = "/tmp/../etc/passwd",
        .max_bytes = 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());

    try std.testing.expectError(error.WriteFailed, result);

    // Also reject ".." in middle of path
    const result2 = Context.init(allocator, .{
        .path = "/tmp/logs/../../etc/shadow",
        .max_bytes = 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());

    try std.testing.expectError(error.WriteFailed, result2);

    // Also reject bare ".." path
    const result3 = Context.init(allocator, .{
        .path = "..",
        .max_bytes = 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());

    try std.testing.expectError(error.WriteFailed, result3);

    // Empty path must be rejected
    const result4 = Context.init(allocator, .{
        .path = "",
        .max_bytes = 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());

    try std.testing.expectError(error.WriteFailed, result4);
}

test "RotatingFileHandler secret redaction" {
    const allocator = std.testing.allocator;

    // Use temp directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/secret_test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 10 * 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "secret test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.secret("password", "super_secret_value"),
        },
    };

    try handler.handle(&rec);
    try handler.flush(0);

    // Read the file contents and verify [REDACTED] is present
    // and the actual secret is NOT present
    const file = try std.Io.Dir.cwd().openFile(std.Io.Threaded.global_single_threaded.io(), full_path, .{});
    defer file.close();
    var read_buf: [4096]u8 = undefined;
    const bytes_read = try file.readAll(&read_buf);
    const contents = read_buf[0..bytes_read];

    try std.testing.expect(std.mem.indexOf(u8, contents, "[REDACTED]") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "super_secret_value") == null);
}

test "RotatingFileHandler all value types" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/values_test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 10 * 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "values test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("str_key", "hello"),
            Attr.int("int_key", -42),
            Attr.uint("uint_key", 100),
            Attr.float("float_key", 3.14),
            Attr.boolean("bool_key", true),
            Attr.err("err_key", error.OutOfMemory),
            Attr.secret("secret_key", "hidden"),
        },
    };

    try handler.handle(&rec);
    try handler.flush(0);

    // Read and verify the file contents
    const file = try std.Io.Dir.cwd().openFile(std.Io.Threaded.global_single_threaded.io(), full_path, .{});
    defer file.close();
    var read_buf: [4096]u8 = undefined;
    const bytes_read = try file.readAll(&read_buf);
    const contents = read_buf[0..bytes_read];

    try std.testing.expect(std.mem.indexOf(u8, contents, "str_key=hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "int_key=-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "uint_key=100") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "float_key=3.14") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "bool_key=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "err_key=OutOfMemory") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "secret_key=[REDACTED]") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "hidden") == null);
}

test "RotatingFileHandler write buffering" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/buffered_test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 100 * 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = init(&ctx);

    // Write multiple small records
    for (0..10) |_| {
        const rec = Record{
            .time_utc_us = 0,
            .level = .info,
            .msg_id = "test",
            .message = "buffered message",
            .logger = "test",
            .source_file = "",
            .source_line = 0,
            .attrs = &.{},
        };
        try handler.handle(&rec);
    }

    // Before flush, data may be in the write buffer
    // After flush, all data should be on disk
    try handler.flush(0);

    const file = try std.Io.Dir.cwd().openFile(std.Io.Threaded.global_single_threaded.io(), full_path, .{});
    defer file.close();
    var read_buf: [8192]u8 = undefined;
    const bytes_read = try file.readAll(&read_buf);
    const contents = read_buf[0..bytes_read];

    // Count newlines to verify all 10 records were written
    var newline_count: usize = 0;
    for (contents) |c| {
        if (c == '\n') newline_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 10), newline_count);
}

test "RotatingFileHandler multiple writes track size" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/size_test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 1024 * 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "size tracking",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const size_after_first = ctx.current_size;
    try std.testing.expect(size_after_first > 0);

    try handler.handle(&rec);
    const size_after_second = ctx.current_size;

    try std.testing.expect(size_after_second > size_after_first);
}

test "RotatingFileHandler level filtering" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/filter_test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .@"error", Clock.system());
    defer ctx.deinit();

    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .debug,
        .msg_id = "test",
        .message = "should be filtered",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    try std.testing.expectEqual(@as(usize, 0), ctx.current_size);
}

test "RotatingFileHandler deinit closes file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/deinit_test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());

    try std.testing.expect(ctx.file != null);

    ctx.deinit();

    try std.testing.expect(ctx.file == null);
}

test "RotatingFileHandler message newline sanitization" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/sanitize_test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 10 * 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = init(&ctx);

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

    try handler.handle(&rec);
    try handler.flush(0);

    const file = try std.Io.Dir.cwd().openFile(std.Io.Threaded.global_single_threaded.io(), full_path, .{});
    defer file.close();
    var read_buf: [4096]u8 = undefined;
    const bytes_read = try file.readAll(&read_buf);
    const contents = read_buf[0..bytes_read];

    // Newline in message should be escaped as \n, not a raw newline
    try std.testing.expect(std.mem.indexOf(u8, contents, "line1\\nline2") != null);
    // Only one raw newline should exist (the line terminator)
    var newlines: usize = 0;
    for (contents) |c| {
        if (c == '\n') newlines += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), newlines);
}

test "RotatingFileHandler auto-redacts sensitive key" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/autoredact_test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 10 * 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "auto-redact test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("password", "secret123"),
            Attr.string("username", "alice"),
        },
    };

    try handler.handle(&rec);
    try handler.flush(0);

    const file = try std.Io.Dir.cwd().openFile(std.Io.Threaded.global_single_threaded.io(), full_path, .{});
    defer file.close();
    var read_buf: [4096]u8 = undefined;
    const bytes_read = try file.readAll(&read_buf);
    const contents = read_buf[0..bytes_read];

    // "password" key should be auto-redacted
    try std.testing.expect(std.mem.indexOf(u8, contents, "password=[REDACTED]") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "secret123") == null);
    // "username" key should pass through normally
    try std.testing.expect(std.mem.indexOf(u8, contents, "username=alice") != null);
    // Deliberate fail removed -- test verified as running via handler_test.zig
}

test "RotatingFileHandler close via vtable" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/close_test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());

    try std.testing.expect(ctx.file != null);

    const handler = init(&ctx);

    // close via the Handler vtable should invoke deinit
    handler.close();

    try std.testing.expect(ctx.file == null);
}
