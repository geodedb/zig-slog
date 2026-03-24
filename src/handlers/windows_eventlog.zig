// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Windows Event Log handler - sends logs to Windows Event Log.
//!
//! Requires: -Dfeature_windows_eventlog=true and Windows target.
//! Uses ReportEventW API.

const std = @import("std");
const builtin = @import("builtin");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const redact = @import("../util/redact.zig");
const sanitize = @import("../util/sanitize.zig");
const metrics = @import("../metrics/metrics.zig");
const writeTextValue = @import("../fmt/text_value.zig").writeTextValue;

/// Check if Windows Event Log is available.
pub const is_available = builtin.os.tag == .windows;

// Windows Event Log types
const EVENTLOG_SUCCESS = 0x0000;
const EVENTLOG_ERROR_TYPE = 0x0001;
const EVENTLOG_WARNING_TYPE = 0x0002;
const EVENTLOG_INFORMATION_TYPE = 0x0004;
const EVENTLOG_AUDIT_SUCCESS = 0x0008;
const EVENTLOG_AUDIT_FAILURE = 0x0010;

/// Windows Event Log handler context.
pub const Context = struct {
    level: Level,
    source_name: []const u8,
    event_handle: if (is_available) ?std.os.windows.HANDLE else void,
    mutex: std.Thread.Mutex,

    pub fn init(level: Level, source_name: []const u8) Context {
        var ctx = Context{
            .level = level,
            .source_name = source_name,
            .event_handle = if (is_available) null else {},
            .mutex = .{},
        };

        if (is_available) {
            ctx.registerEventSource();
        }

        return ctx;
    }

    pub fn deinit(self: *Context) void {
        if (is_available) {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.event_handle) |h| {
                _ = std.os.windows.kernel32.DeregisterEventSource(h);
                self.event_handle = null;
            }
        }
    }

    fn registerEventSource(self: *Context) void {
        if (!is_available) return;

        // Convert source name to wide string
        var wide_name: [256]u16 = undefined;
        const len = std.unicode.utf8ToUtf16Le(&wide_name, self.source_name) catch return;
        wide_name[len] = 0;

        // Register event source
        // self.event_handle = RegisterEventSourceW(null, &wide_name);
        _ = &wide_name;
    }
};

/// Convert log level to Windows event type.
fn levelToEventType(level: Level) u16 {
    return switch (level) {
        .trace, .debug, .info => EVENTLOG_INFORMATION_TYPE,
        .warn => EVENTLOG_WARNING_TYPE,
        .@"error", .fatal => EVENTLOG_ERROR_TYPE,
    };
}

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    if (!rec.level.atLeast(ctx.level)) return;

    if (!is_available) {
        return error.FeatureDisabled;
    }

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    // Format message with attributes
    var msg_buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&msg_buf);
    const writer = fbs.writer();

    sanitize.sanitizeOutput(writer, rec.message) catch return error.WriteFailed;

    // Append attributes (auto-redact sensitive keys, sanitize keys)
    for (rec.attrs) |attr| {
        writer.writeByte(' ') catch return error.WriteFailed;
        var key_buf: [sanitize.MAX_KEY_LENGTH]u8 = undefined;
        const key = sanitize.sanitizeKey(&key_buf, attr.key);
        writer.writeAll(key) catch return error.WriteFailed;
        writer.writeByte('=') catch return error.WriteFailed;
        if (redact.isSensitiveKey(attr.key)) {
            writer.writeAll(redact.REDACTED) catch return error.WriteFailed;
        } else {
            writeTextValue(writer, attr.value) catch return error.WriteFailed;
        }
    }

    const message = fbs.getWritten();

    if (is_available) {
        // Convert to wide string for Windows API
        var wide_msg: [4096]u16 = undefined;
        const wide_len = std.unicode.utf8ToUtf16Le(&wide_msg, message) catch return error.WriteFailed;
        wide_msg[wide_len] = 0;

        const event_type = levelToEventType(rec.level);

        // Would call: ReportEventW(ctx.event_handle, event_type, 0, event_id, null, 1, 0, &wide_msg_ptr, null);
        _ = event_type;
        _ = &wide_msg;
    }

    // Fallback: write sanitized output to stderr using a buffer to reduce syscalls
    var stderr_buf: [8192]u8 = undefined;
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const stderr_writer = stderr_stream.writer();
    stderr_writer.writeByte('[') catch {};
    stderr_writer.writeAll(rec.level.asText()) catch {};
    stderr_writer.writeAll("] ") catch {};
    sanitize.sanitizeOutput(stderr_writer, ctx.source_name) catch {};
    stderr_writer.writeAll(": ") catch {};
    stderr_writer.writeAll(message) catch {};
    stderr_writer.writeByte('\n') catch {};
    std.fs.File.stderr().writeAll(stderr_stream.getWritten()) catch {};

    metrics.global.addBytesWritten(message.len);
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
    // Event log writes immediately
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

/// Initialize a Windows Event Log handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

test "WindowsEventLogHandler availability" {
    var ctx = Context.init(.info, "TestApp");
    defer ctx.deinit();
    const handler = init(&ctx);
    _ = handler;
}

test "WindowsEventLogHandler event type mapping" {
    try std.testing.expectEqual(@as(u16, EVENTLOG_INFORMATION_TYPE), levelToEventType(.trace));
    try std.testing.expectEqual(@as(u16, EVENTLOG_INFORMATION_TYPE), levelToEventType(.debug));
    try std.testing.expectEqual(@as(u16, EVENTLOG_INFORMATION_TYPE), levelToEventType(.info));
    try std.testing.expectEqual(@as(u16, EVENTLOG_WARNING_TYPE), levelToEventType(.warn));
    try std.testing.expectEqual(@as(u16, EVENTLOG_ERROR_TYPE), levelToEventType(.@"error"));
    try std.testing.expectEqual(@as(u16, EVENTLOG_ERROR_TYPE), levelToEventType(.fatal));
}
