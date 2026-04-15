// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Syslog RFC5424 handler - structured syslog output.
//!
//! Format: <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID [STRUCTURED-DATA] MSG
//! PRI = facility * 8 + severity
//! Structured-data: [attrs@32473 key="value" ...]

const std = @import("std");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Value = @import("../value.zig").Value;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const Clock = @import("../internal/clock.zig").Clock;
const rfc3339 = @import("../fmt/rfc3339.zig");
const redact = @import("../util/redact.zig");
const sanitize = @import("../util/sanitize.zig");
const metrics = @import("../metrics/metrics.zig");

/// Syslog facility codes (RFC5424).
pub const Facility = enum(u8) {
    kern = 0, // kernel messages
    user = 1, // user-level messages
    mail = 2, // mail system
    daemon = 3, // system daemons
    auth = 4, // security/authorization
    syslog = 5, // syslogd internal
    lpr = 6, // line printer
    news = 7, // network news
    uucp = 8, // UUCP subsystem
    cron = 9, // clock daemon
    authpriv = 10, // security/authorization (private)
    ftp = 11, // FTP daemon
    ntp = 12, // NTP subsystem
    audit = 13, // log audit
    alert = 14, // log alert
    clock = 15, // clock daemon (note 2)
    local0 = 16,
    local1 = 17,
    local2 = 18,
    local3 = 19,
    local4 = 20,
    local5 = 21,
    local6 = 22,
    local7 = 23,
};

/// Syslog severity codes (RFC5424).
pub const Severity = enum(u8) {
    emergency = 0,
    alert = 1,
    critical = 2,
    @"error" = 3,
    warning = 4,
    notice = 5,
    info = 6,
    debug = 7,
};

/// Enterprise number for structured data (IANA registered or private).
pub const ENTERPRISE_NUMBER = 32473;

/// Syslog options.
pub const SyslogOptions = struct {
    facility: Facility = .local0,
    hostname: []const u8 = "-",
    app_name: []const u8 = "-",
    procid: ?u32 = null,
};

/// Syslog handler context.
pub const Context = struct {
    writer: *std.Io.Writer,
    level: std.atomic.Value(i32),
    clock: Clock,
    options: SyslogOptions,
    context_attrs: []const Attr,
    mutex: std.Io.Mutex,

    pub fn init(writer: *std.Io.Writer, level: Level, clock: Clock, options: SyslogOptions) Context {
        return .{
            .writer = writer,
            .level = std.atomic.Value(i32).init(@intFromEnum(level)),
            .clock = clock,
            .options = options,
            .context_attrs = &.{},
            .mutex = std.Io.Mutex.init,
        };
    }
};

/// Convert log level to syslog severity.
fn levelToSeverity(level: Level) Severity {
    return switch (level) {
        .trace, .debug => .debug,
        .info => .info,
        .warn => .warning,
        .@"error" => .@"error",
        .fatal => .critical,
    };
}

/// Calculate PRI value.
fn calcPri(facility: Facility, severity: Severity) u8 {
    return @as(u8, @intFromEnum(facility)) * 8 + @as(u8, @intFromEnum(severity));
}

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    const current_level: Level = @enumFromInt(ctx.level.load(.acquire));
    if (!rec.level.atLeast(current_level)) return;

    ctx.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer ctx.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    var buf: [16384]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    const writer = &fbs;

    // PRI
    const severity = levelToSeverity(rec.level);
    const pri = calcPri(ctx.options.facility, severity);
    writer.print("<{d}>1 ", .{pri}) catch return error.WriteFailed;

    // TIMESTAMP (RFC3339 with microseconds)
    var ts_buf: [27]u8 = undefined;
    rfc3339.formatTimestamp(&ts_buf, rec.time_utc_us);
    writer.writeAll(&ts_buf) catch return error.WriteFailed;
    writer.writeByte(' ') catch return error.WriteFailed;

    // HOSTNAME (sanitize to printable ASCII per RFC5424)
    writeSyslogName(writer, ctx.options.hostname) catch return error.WriteFailed;
    writer.writeByte(' ') catch return error.WriteFailed;

    // APP-NAME
    if (rec.logger.len > 0) {
        writeSyslogName(writer, rec.logger) catch return error.WriteFailed;
    } else if (ctx.options.app_name.len > 0) {
        writeSyslogName(writer, ctx.options.app_name) catch return error.WriteFailed;
    } else {
        writer.writeByte('-') catch return error.WriteFailed;
    }
    writer.writeByte(' ') catch return error.WriteFailed;

    // PROCID
    if (ctx.options.procid) |pid| {
        writer.print("{d}", .{pid}) catch return error.WriteFailed;
    } else {
        writer.writeByte('-') catch return error.WriteFailed;
    }
    writer.writeByte(' ') catch return error.WriteFailed;

    // MSGID
    if (rec.msg_id.len > 0) {
        writeSyslogName(writer, rec.msg_id) catch return error.WriteFailed;
    } else {
        writer.writeByte('-') catch return error.WriteFailed;
    }
    writer.writeByte(' ') catch return error.WriteFailed;

    // STRUCTURED-DATA
    const has_attrs = ctx.context_attrs.len > 0 or rec.attrs.len > 0;
    if (has_attrs) {
        writer.print("[attrs@{d}", .{ENTERPRISE_NUMBER}) catch return error.WriteFailed;

        // Context attrs
        for (ctx.context_attrs) |attr| {
            writer.writeByte(' ') catch return error.WriteFailed;
            writeStructuredDataParam(writer, attr) catch return error.WriteFailed;
        }

        // Record attrs
        for (rec.attrs) |attr| {
            writer.writeByte(' ') catch return error.WriteFailed;
            writeStructuredDataParam(writer, attr) catch return error.WriteFailed;
        }

        writer.writeByte(']') catch return error.WriteFailed;
    } else {
        writer.writeByte('-') catch return error.WriteFailed;
    }

    // MSG (BOM optional, we skip it; sanitize to prevent log injection)
    writer.writeByte(' ') catch return error.WriteFailed;
    sanitize.sanitizeOutput(writer, rec.message) catch return error.WriteFailed;
    writer.writeByte('\n') catch return error.WriteFailed;

    const output = fbs.buffered();
    ctx.writer.writeAll(output) catch return error.WriteFailed;
    metrics.global.addBytesWritten(output.len);
}

/// Write syslog name (APP-NAME, MSGID) - max 48 chars, printable ASCII.
fn writeSyslogName(writer: anytype, name: []const u8) !void {
    const max_len: usize = 48;
    var written: usize = 0;

    for (name) |c| {
        if (written >= max_len) break;
        // Printable ASCII only (33-126)
        if (c >= 33 and c <= 126) {
            try writer.writeByte(c);
            written += 1;
        }
    }

    if (written == 0) {
        try writer.writeByte('-');
    }
}

/// Write structured-data parameter: key="value"
fn writeStructuredDataParam(writer: anytype, attr: Attr) !void {
    // Key (sanitized)
    var key_buf: [sanitize.MAX_KEY_LENGTH]u8 = undefined;
    const key = sanitize.sanitizeKey(&key_buf, attr.key);
    try writer.writeAll(key);
    try writer.writeAll("=\"");

    // Auto-redact sensitive keys; otherwise escape per RFC5424
    if (redact.isSensitiveKey(attr.key)) {
        try writer.writeAll(redact.REDACTED);
    } else {
        try writeSDValue(writer, attr.value);
    }
    try writer.writeByte('"');
}

/// Write structured-data value with RFC5424 escaping.
fn writeSDValue(writer: anytype, value: Value) !void {
    switch (value) {
        .str => |s| try writeSDString(writer, s),
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
            const hex_chars = "0123456789abcdef";
            for (b) |byte| {
                try writer.writeAll(&[2]u8{ hex_chars[byte >> 4], hex_chars[byte & 0x0f] });
            }
        },
        .err => |e| {
            const raw: u16 = @intFromError(e);
            if (raw == 0) {
                try writer.writeAll("error(0)");
            } else {
                try writer.writeAll(@errorName(e));
            }
        },
        .secret => try writer.writeAll(redact.REDACTED),
        .marshaler => try writer.writeAll("?"),
    }
}

/// Write string with RFC5424 structured-data escaping.
/// Must escape: \ " ] and control characters (< 0x20, except 0x09 tab).
fn writeSDString(writer: anytype, s: []const u8) !void {
    const hex_chars = "0123456789abcdef";
    for (s) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            ']' => try writer.writeAll("\\]"),
            '\t' => try writer.writeByte(c), // tab allowed in RFC5424
            0x00...0x08, 0x0a...0x1f => {
                // Escape control characters as \xHH
                try writer.writeAll("\\x");
                try writer.writeAll(&[2]u8{ hex_chars[c >> 4], hex_chars[c & 0x0f] });
            },
            else => try writer.writeByte(c),
        }
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
}

fn flush(_: *anyopaque, _: u32) HandlerError!void {
    // Syslog writes immediately
}

const vtable = HandlerVTable{
    .handle = handle,
    .withAttrs = withAttrs,
    .withGroup = withGroup,
    .setLevel = setLevel,
    .flush = flush,
};

/// Initialize a syslog RFC5424 handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

test "SyslogHandler basic output" {
    var buf: [2048]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .info, @import("../internal/clock.zig").Clock.system(), .{
        .facility = .local0,
        .hostname = "localhost",
        .app_name = "test",
        .procid = 1234,
    });
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "app.started",
        .message = "iniciado en 12ms",
        .logger = "web",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.int("duration_ms", 12),
        },
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    // PRI for local0.info = 16*8 + 6 = 134
    try std.testing.expect(std.mem.startsWith(u8, output, "<134>1 "));
    try std.testing.expect(std.mem.indexOf(u8, output, "localhost") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "web") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1234") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "app.started") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[attrs@32473") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "duration_ms=\"12\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "iniciado en 12ms") != null);
}

test "SyslogHandler escaping" {
    var buf: [1024]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .info, @import("../internal/clock.zig").Clock.system(), .{
        .hostname = "localhost",
    });
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
            Attr.string("data", "test\"with]special\\chars"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    // Check escaping
    try std.testing.expect(std.mem.indexOf(u8, output, "\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\\\") != null);
}

test "SyslogHandler severity mapping" {
    try std.testing.expectEqual(Severity.debug, levelToSeverity(.trace));
    try std.testing.expectEqual(Severity.debug, levelToSeverity(.debug));
    try std.testing.expectEqual(Severity.info, levelToSeverity(.info));
    try std.testing.expectEqual(Severity.warning, levelToSeverity(.warn));
    try std.testing.expectEqual(Severity.@"error", levelToSeverity(.@"error"));
    try std.testing.expectEqual(Severity.critical, levelToSeverity(.fatal));
}
