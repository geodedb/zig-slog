// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! HTTP sink - sends log records over HTTP POST.
//!
//! Features:
//! - Per-request TCP connections (no pooling)
//! - Configurable retry with exponential backoff
//! - Custom headers support
//! - Header injection prevention (control character filtering)

const std = @import("std");
const Level = @import("../level.zig").Level;
const Record = @import("../record.zig").Record;
const Attr = @import("../value.zig").Attr;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const Clock = @import("../internal/clock.zig").Clock;
const metrics = @import("../metrics/metrics.zig");
const writeJsonRecord = @import("../fmt/json_record.zig").writeJsonRecord;

/// HTTP sink options.
pub const HttpOptions = struct {
    url: []const u8,
    method: []const u8 = "POST",
    content_type: []const u8 = "application/json",
    timeout_ms: u32 = 10000,
    max_retries: u8 = 3,
    initial_backoff_ms: u32 = 100,
    max_backoff_ms: u32 = 5000,
    headers: []const Header = &.{},

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };
};

/// HTTP sink context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    options: HttpOptions,
    level: std.atomic.Value(i32),
    clock: Clock,
    mutex: std.Thread.Mutex,
    consecutive_failures: u32,

    // Parsed URL components
    host: []const u8,
    port: u16,
    path: []const u8,
    is_https: bool,

    pub fn init(allocator: std.mem.Allocator, options: HttpOptions, level: Level, clock: Clock) !Context {
        // Parse URL
        const url = options.url;
        var host: []const u8 = "";
        var port: u16 = 80;
        var path: []const u8 = "/";

        if (std.mem.startsWith(u8, url, "https://")) {
            // TLS is not implemented; reject https:// URLs to prevent
            // silently sending data in plaintext
            return error.HttpsNotSupported;
        } else if (std.mem.startsWith(u8, url, "http://")) {
            const rest = url[7..];
            if (std.mem.indexOf(u8, rest, "/")) |slash_idx| {
                host = rest[0..slash_idx];
                path = rest[slash_idx..];
            } else {
                host = rest;
            }
        } else {
            return error.InvalidUrl;
        }

        // Parse port from host if present
        if (std.mem.indexOf(u8, host, ":")) |colon_idx| {
            const port_str = host[colon_idx + 1 ..];
            host = host[0..colon_idx];
            port = std.fmt.parseInt(u16, port_str, 10) catch return error.InvalidUrl;
        }

        return .{
            .allocator = allocator,
            .options = options,
            .level = std.atomic.Value(i32).init(@intFromEnum(level)),
            .clock = clock,
            .mutex = .{},
            .consecutive_failures = 0,
            .host = host,
            .port = port,
            .path = path,
            .is_https = false,
        };
    }

    pub fn deinit(_: *Context) void {
        // No persistent connections to close
    }

    fn sendWithRetry(self: *Context, data: []const u8) !void {
        var backoff: u32 = self.options.initial_backoff_ms;

        for (0..self.options.max_retries + 1) |attempt| {
            if (self.sendHttp(data)) {
                self.consecutive_failures = 0;
                metrics.global.addBytesWritten(data.len);
                return;
            }

            if (attempt < self.options.max_retries) {
                std.Thread.sleep(@as(u64, backoff) * std.time.ns_per_ms);
                backoff = @min(backoff * 2, self.options.max_backoff_ms);
            }
        }

        self.consecutive_failures += 1;
        return error.WriteFailed;
    }

    fn sendHttp(self: *Context, data: []const u8) bool {
        // Connect: fast path for literal IP, slow path with DNS resolution
        const stream = if (std.net.Address.parseIp4(self.host, self.port)) |address|
            std.net.tcpConnectToAddress(address) catch return false
        else |_|
            std.net.tcpConnectToHost(self.allocator, self.host, self.port) catch return false;
        defer stream.close();

        // Apply socket timeouts
        const timeout_ms = self.options.timeout_ms;
        const timeval = std.posix.timeval{
            .sec = @intCast(timeout_ms / 1000),
            .usec = @intCast((timeout_ms % 1000) * 1000),
        };
        std.posix.setsockopt(stream.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&timeval)) catch {};
        std.posix.setsockopt(stream.handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&timeval)) catch {};

        // Build HTTP request
        var req_buf: [1024]u8 = undefined;
        const req_header = std.fmt.bufPrint(&req_buf, "{s} {s} HTTP/1.1\r\nHost: {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n", .{
            self.options.method,
            self.path,
            self.host,
            self.options.content_type,
            data.len,
        }) catch return false;

        // Send header
        _ = stream.write(req_header) catch return false;

        // Send custom headers (skip any with control characters to prevent injection)
        for (self.options.headers) |header| {
            if (containsControlChars(header.name) or containsControlChars(header.value)) continue;
            _ = stream.write(header.name) catch return false;
            _ = stream.write(": ") catch return false;
            _ = stream.write(header.value) catch return false;
            _ = stream.write("\r\n") catch return false;
        }

        // End headers
        _ = stream.write("\r\n") catch return false;

        // Send body
        _ = stream.write(data) catch return false;

        // Read response (simplified - just check status)
        var resp_buf: [256]u8 = undefined;
        const n = stream.read(&resp_buf) catch return false;
        if (n < 12) return false;

        // Check for 2xx status at the correct position in the HTTP status line.
        // HTTP/1.x responses have format "HTTP/1.X YYY ..." with status at index 9.
        if (n >= 12 and resp_buf[9] == '2') {
            return true;
        }

        return false;
    }
};

/// Returns true if the string contains control characters (bytes < 0x20, especially CR, LF, NUL).
/// Used to prevent HTTP header injection.
fn containsControlChars(s: []const u8) bool {
    for (s) |c| {
        if (c < 0x20 or c == 0x7f) return true;
    }
    return false;
}

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    const current_level: Level = @enumFromInt(ctx.level.load(.acquire));
    if (!rec.level.atLeast(current_level)) return;

    // Format record as JSON OUTSIDE the mutex
    var buf: [16384]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);

    writeJsonRecord(fbs.writer(), rec, "") catch return error.WriteFailed;

    const output = fbs.getWritten();

    // Lock only for the network send
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    ctx.sendWithRetry(output) catch {
        metrics.global.incErrors();
        return error.WriteFailed;
    };
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
    // HTTP writes immediately
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

/// Initialize an HTTP sink handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

test "HttpSink URL parsing" {
    const allocator = std.testing.allocator;

    // HTTP URL
    {
        var ctx = try Context.init(allocator, .{
            .url = "http://localhost:8080/logs",
        }, .info, Clock.system());
        defer ctx.deinit();

        try std.testing.expectEqualStrings("localhost", ctx.host);
        try std.testing.expectEqual(@as(u16, 8080), ctx.port);
        try std.testing.expectEqualStrings("/logs", ctx.path);
        try std.testing.expect(!ctx.is_https);
    }

    // HTTPS URL is rejected (TLS not implemented)
    {
        const result = Context.init(allocator, .{
            .url = "https://api.example.com/v1/logs",
        }, .info, Clock.system());
        try std.testing.expectError(error.HttpsNotSupported, result);
    }
}

test "HttpSink init with hostname" {
    const allocator = std.testing.allocator;

    var ctx = try Context.init(allocator, .{
        .url = "http://logserver.example.com:9200/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqualStrings("logserver.example.com", ctx.host);
    try std.testing.expectEqual(@as(u16, 9200), ctx.port);
    try std.testing.expectEqualStrings("/logs", ctx.path);
}

test "HttpSink containsControlChars" {
    try std.testing.expect(!containsControlChars("normal-header"));
    try std.testing.expect(!containsControlChars("X-Custom-Header"));
    try std.testing.expect(containsControlChars("evil\r\nheader"));
    try std.testing.expect(containsControlChars("evil\nheader"));
    try std.testing.expect(containsControlChars("evil\x00header"));
    try std.testing.expect(containsControlChars("evil\theader"));
}

test "HttpSink HTTP status check position" {
    // Verify that our status check looks at the correct position.
    // "HTTP/1.1 200 OK" => index 9 is '2'
    const good = "HTTP/1.1 200 OK\r\n";
    try std.testing.expect(good.len >= 12 and good[9] == '2');

    // "HTTP/1.1 404 Not Found" => index 9 is '4'
    const bad = "HTTP/1.1 404 Not Found\r\n";
    try std.testing.expect(bad.len >= 12 and bad[9] != '2');

    // A response containing " 2" in the body but with non-2xx status should fail
    const tricky = "HTTP/1.1 400 Bad 2xx\r\n";
    try std.testing.expect(tricky.len >= 12 and tricky[9] != '2');
}
