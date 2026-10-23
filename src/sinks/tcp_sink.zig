// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! TCP sink - sends log records over TCP with reconnection and retry.
//!
//! Features:
//! - Automatic reconnection on failure
//! - Configurable retry with exponential backoff
//! - Connection timeout support

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

/// TCP sink options.
pub const TcpOptions = struct {
    host: []const u8,
    port: u16,
    connect_timeout_ms: u32 = 5000,
    max_retries: u8 = 3,
    initial_backoff_ms: u32 = 100,
    max_backoff_ms: u32 = 5000,
};

/// TCP sink context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    options: TcpOptions,
    stream: ?std.Io.net.Stream,
    level: std.atomic.Value(i32),
    clock: Clock,
    mutex: std.Io.Mutex,
    consecutive_failures: u32,
    circuit_open_until: i64,

    /// Circuit breaker threshold: number of consecutive failures before opening circuit.
    const circuit_breaker_threshold: u32 = 3;
    /// Circuit breaker cooldown period in milliseconds.
    const circuit_cooldown_ms: i64 = 30_000;

    pub fn init(allocator: std.mem.Allocator, options: TcpOptions, level: Level, clock: Clock) Context {
        return .{
            .allocator = allocator,
            .options = options,
            .stream = null,
            .level = std.atomic.Value(i32).init(@intFromEnum(level)),
            .clock = clock,
            .mutex = std.Io.Mutex.init,
            .consecutive_failures = 0,
            .circuit_open_until = 0,
        };
    }

    pub fn deinit(self: *Context) void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        if (self.stream) |s| {
            s.close(std.Io.Threaded.global_single_threaded.io());
            self.stream = null;
        }
    }

    fn connect(self: *Context) !void {
        if (self.stream != null) return;
        const io = std.Io.Threaded.global_single_threaded.io();

        // Try parsing as literal IPv4 or IPv6 address and connect
        const address = std.Io.net.IpAddress.parseIp4(self.options.host, self.options.port) catch
            std.Io.net.IpAddress.parseIp6(self.options.host, self.options.port) catch
            std.Io.net.IpAddress.resolve(io, self.options.host, self.options.port) catch
            return error.ConnectionFailed;
        self.stream = address.connect(io, .{ .mode = .stream }) catch return error.ConnectionFailed;
        self.applySocketTimeouts();
    }

    /// Apply send/receive timeouts to the connected socket.
    fn applySocketTimeouts(self: *Context) void {
        if (self.stream) |s| {
            const timeout_ms = self.options.connect_timeout_ms;
            const timeval = std.posix.timeval{
                .sec = @intCast(timeout_ms / 1000),
                .usec = @intCast((timeout_ms % 1000) * 1000),
            };
            std.posix.setsockopt(s.socket.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&timeval)) catch {};
            std.posix.setsockopt(s.socket.handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&timeval)) catch {};
        }
    }

    fn disconnect(self: *Context) void {
        if (self.stream) |s| {
            s.close(std.Io.Threaded.global_single_threaded.io());
            self.stream = null;
        }
    }

    fn writeWithRetry(self: *Context, data: []const u8) !void {
        // Circuit breaker: fast-fail during cooldown period
        const now = std.Io.Clock.real.now(std.Io.Threaded.global_single_threaded.io()).toMilliseconds();
        if (self.consecutive_failures >= circuit_breaker_threshold and now < self.circuit_open_until) {
            return error.WriteFailed;
        }

        var backoff: u32 = self.options.initial_backoff_ms;
        var attempts: u8 = 0;

        while (attempts <= self.options.max_retries) : (attempts += 1) {
            // Try to connect if not connected
            const was_disconnected = self.stream == null;
            self.connect() catch {
                if (attempts < self.options.max_retries) {
                    {
                        const sio = std.Io.Threaded.global_single_threaded.io();
                        sio.sleep(std.Io.Duration.fromMilliseconds(@as(i64, @intCast(backoff))), .awake) catch {};
                    }
                    backoff = @min(backoff * 2, self.options.max_backoff_ms);
                    continue;
                }
                return error.ConnectionFailed;
            };

            // Track reconnections (connect succeeded after prior disconnect)
            if (was_disconnected and attempts > 0) {
                metrics.global.incReconnections();
            }

            // Try to write
            if (self.stream) |s| {
                var wbuf: [4096]u8 = undefined;
                var w = s.writer(std.Io.Threaded.global_single_threaded.io(), &wbuf);
                w.interface.writeAll(data) catch {
                    self.disconnect();
                    if (attempts < self.options.max_retries) {
                        {
                            const sio = std.Io.Threaded.global_single_threaded.io();
                            sio.sleep(std.Io.Duration.fromMilliseconds(@as(i64, @intCast(backoff))), .awake) catch {};
                        }
                        backoff = @min(backoff * 2, self.options.max_backoff_ms);
                        continue;
                    }
                    return error.WriteFailed;
                };

                self.consecutive_failures = 0;
                self.circuit_open_until = 0;
                metrics.global.addBytesWritten(data.len);
                return;
            }
        }

        self.consecutive_failures += 1;
        if (self.consecutive_failures >= circuit_breaker_threshold) {
            self.circuit_open_until = std.Io.Clock.real.now(std.Io.Threaded.global_single_threaded.io()).toMilliseconds() + circuit_cooldown_ms;
        }
        return error.WriteFailed;
    }
};

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    const current_level: Level = @enumFromInt(ctx.level.load(.acquire));
    if (!rec.level.atLeast(current_level)) return;

    // Format record as JSON line OUTSIDE the mutex
    var buf: [16384]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    writeJsonRecord(&fbs, rec, "") catch return error.WriteFailed;

    const output = fbs.buffered();

    // Lock only for the network write
    ctx.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer ctx.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    ctx.writeWithRetry(output) catch |err| {
        metrics.global.incErrors();
        return switch (err) {
            error.ConnectionFailed => error.ConnectionFailed,
            else => error.WriteFailed,
        };
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
    // TCP writes immediately
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

/// Initialize a TCP sink handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

test "TcpSink init" {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator, .{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = init(&ctx);
    _ = handler;
}

test "TcpSink init with hostname" {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator, .{
        .host = "logserver.example.com",
        .port = 5514,
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqualStrings("logserver.example.com", ctx.options.host);
    try std.testing.expectEqual(@as(u16, 5514), ctx.options.port);
}
