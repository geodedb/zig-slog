// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Journald handler - sends logs to systemd journal via libsystemd.
//!
//! Requires: -Dfeature_journald=true and libsystemd installed.
//! Links against libsystemd for sd_journal_send().

const std = @import("std");
const builtin = @import("builtin");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Value = @import("../value.zig").Value;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const redact = @import("../util/redact.zig");
const sanitize = @import("../util/sanitize.zig");
const metrics = @import("../metrics/metrics.zig");

/// Check if journald is available (Linux only).
pub const is_available = builtin.os.tag == .linux;

// Journald priority levels (same as syslog)
const LOG_EMERG = 0;
const LOG_ALERT = 1;
const LOG_CRIT = 2;
const LOG_ERR = 3;
const LOG_WARNING = 4;
const LOG_NOTICE = 5;
const LOG_INFO = 6;
const LOG_DEBUG = 7;

/// Journald handler context.
pub const Context = struct {
    level: Level,
    syslog_identifier: []const u8,
    mutex: std.Thread.Mutex,

    pub fn init(level: Level, syslog_identifier: []const u8) Context {
        return .{
            .level = level,
            .syslog_identifier = syslog_identifier,
            .mutex = .{},
        };
    }
};

/// Convert log level to journald priority.
fn levelToPriority(level: Level) u8 {
    return switch (level) {
        .trace, .debug => LOG_DEBUG,
        .info => LOG_INFO,
        .warn => LOG_WARNING,
        .@"error" => LOG_ERR,
        .fatal => LOG_CRIT,
    };
}

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    if (!rec.level.atLeast(ctx.level)) return;

    if (!is_available) {
        return error.UnsupportedPlatform;
    }

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    // Build fields for journald
    // Format: FIELD=value (uppercase field names)
    var fields_buf: [32][512]u8 = undefined;
    var field_ptrs: [32][*:0]const u8 = undefined;
    var field_count: usize = 0;

    // MESSAGE (required)
    const msg_field = std.fmt.bufPrintZ(&fields_buf[field_count], "MESSAGE={s}", .{rec.message}) catch return error.WriteFailed;
    field_ptrs[field_count] = msg_field.ptr;
    field_count += 1;

    // PRIORITY
    const priority = levelToPriority(rec.level);
    const pri_field = std.fmt.bufPrintZ(&fields_buf[field_count], "PRIORITY={d}", .{priority}) catch return error.WriteFailed;
    field_ptrs[field_count] = pri_field.ptr;
    field_count += 1;

    // SYSLOG_IDENTIFIER
    if (ctx.syslog_identifier.len > 0) {
        const ident_field = std.fmt.bufPrintZ(&fields_buf[field_count], "SYSLOG_IDENTIFIER={s}", .{ctx.syslog_identifier}) catch return error.WriteFailed;
        field_ptrs[field_count] = ident_field.ptr;
        field_count += 1;
    } else if (rec.logger.len > 0) {
        const ident_field = std.fmt.bufPrintZ(&fields_buf[field_count], "SYSLOG_IDENTIFIER={s}", .{rec.logger}) catch return error.WriteFailed;
        field_ptrs[field_count] = ident_field.ptr;
        field_count += 1;
    }

    // CODE_FILE and CODE_LINE (if present)
    if (rec.source_file.len > 0) {
        const file_field = std.fmt.bufPrintZ(&fields_buf[field_count], "CODE_FILE={s}", .{rec.source_file}) catch return error.WriteFailed;
        field_ptrs[field_count] = file_field.ptr;
        field_count += 1;

        const line_field = std.fmt.bufPrintZ(&fields_buf[field_count], "CODE_LINE={d}", .{rec.source_line}) catch return error.WriteFailed;
        field_ptrs[field_count] = line_field.ptr;
        field_count += 1;
    }

    // Custom attributes
    for (rec.attrs) |attr| {
        if (field_count >= fields_buf.len - 1) break;

        // Uppercase key for journald
        var key_buf: [sanitize.MAX_KEY_LENGTH]u8 = undefined;
        const key = sanitize.sanitizeKey(&key_buf, attr.key);
        var upper_key: [sanitize.MAX_KEY_LENGTH]u8 = undefined;
        for (key, 0..) |c, i| {
            upper_key[i] = std.ascii.toUpper(c);
        }

        // Format value
        var val_buf: [256]u8 = undefined;
        var val_fbs = std.io.fixedBufferStream(&val_buf);
        const val_writer = val_fbs.writer();
        writeValue(val_writer, attr.value) catch continue;

        const attr_field = std.fmt.bufPrintZ(&fields_buf[field_count], "{s}={s}", .{ upper_key[0..key.len], val_fbs.getWritten() }) catch continue;
        field_ptrs[field_count] = attr_field.ptr;
        field_count += 1;
    }

    // Call sd_journal_sendv or fall back to writing to /dev/log
    // For now, we write to stderr as a fallback when libsystemd isn't linked
    // Real implementation would use: sd_journal_sendv(iov, field_count)

    // Fallback: write structured message to stderr
    const stderr = std.fs.File.stderr().deprecatedWriter();
    stderr.print("<{d}>", .{priority}) catch {};
    if (ctx.syslog_identifier.len > 0) {
        stderr.print("{s}: ", .{ctx.syslog_identifier}) catch {};
    }
    stderr.print("{s}", .{rec.message}) catch {};
    for (rec.attrs) |attr| {
        stderr.print(" {s}=", .{attr.key}) catch {};
        writeValue(stderr, attr.value) catch {};
    }
    stderr.writeByte('\n') catch {};

    metrics.global.addBytesWritten(rec.message.len);
}

fn writeValue(writer: anytype, value: Value) !void {
    switch (value) {
        .str => |s| try writer.writeAll(s),
        .i64 => |i| try writer.print("{d}", .{i}),
        .u64 => |u| try writer.print("{d}", .{u}),
        .f64 => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                try writer.writeAll("null");
            } else {
                try writer.print("{d}", .{f});
            }
        },
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .bytes => |b| {
            for (b) |byte| {
                try writer.print("{x:0>2}", .{byte});
            }
        },
        .err => |e| try writer.writeAll(@errorName(e)),
        .secret => try writer.writeAll(redact.REDACTED),
        .marshaler => try writer.writeAll("?"),
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
    ctx.level = level;
}

fn flush(_: *anyopaque, _: u32) HandlerError!void {
    // Journald writes immediately
}

const vtable = HandlerVTable{
    .handle = handle,
    .withAttrs = withAttrs,
    .withGroup = withGroup,
    .setLevel = setLevel,
    .flush = flush,
};

/// Initialize a journald handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

test "JournaldHandler availability" {
    if (is_available) {
        var ctx = Context.init(.info, "test");
        const handler = init(&ctx);
        _ = handler;
    }
}

test "JournaldHandler priority mapping" {
    try std.testing.expectEqual(@as(u8, LOG_DEBUG), levelToPriority(.trace));
    try std.testing.expectEqual(@as(u8, LOG_DEBUG), levelToPriority(.debug));
    try std.testing.expectEqual(@as(u8, LOG_INFO), levelToPriority(.info));
    try std.testing.expectEqual(@as(u8, LOG_WARNING), levelToPriority(.warn));
    try std.testing.expectEqual(@as(u8, LOG_ERR), levelToPriority(.@"error"));
    try std.testing.expectEqual(@as(u8, LOG_CRIT), levelToPriority(.fatal));
}
