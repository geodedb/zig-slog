// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! TCP sink - sends log records over TCP with reconnection and retry.
//!
//! Features:
//! - Automatic reconnection on failure
//! - Configurable retry with exponential backoff
//! - Connection timeout support

const std = @import("std");
const json = @import("json");
const Level = @import("../level.zig").Level;
const Record = @import("../record.zig").Record;
const Attr = @import("../value.zig").Attr;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const Clock = @import("../internal/clock.zig").Clock;
const rfc3339 = @import("../fmt/rfc3339.zig");
const metrics = @import("../metrics/metrics.zig");

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
    stream: ?std.net.Stream,
    level: Level,
    clock: Clock,
    mutex: std.Thread.Mutex,
    consecutive_failures: u32,

    pub fn init(allocator: std.mem.Allocator, options: TcpOptions, level: Level, clock: Clock) Context {
        return .{
            .allocator = allocator,
            .options = options,
            .stream = null,
            .level = level,
            .clock = clock,
            .mutex = .{},
            .consecutive_failures = 0,
        };
    }

    pub fn deinit(self: *Context) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.stream) |s| {
            s.close();
            self.stream = null;
        }
    }

    fn connect(self: *Context) !void {
        if (self.stream != null) return;

        const address = std.net.Address.parseIp4(self.options.host, self.options.port) catch {
            // Try IPv6
            const addr = std.net.Address.parseIp6(self.options.host, self.options.port) catch {
                return error.ConnectionFailed;
            };
            self.stream = std.net.tcpConnectToAddress(addr) catch return error.ConnectionFailed;
            return;
        };

        self.stream = std.net.tcpConnectToAddress(address) catch return error.ConnectionFailed;
    }

    fn disconnect(self: *Context) void {
        if (self.stream) |s| {
            s.close();
            self.stream = null;
        }
    }

    fn writeWithRetry(self: *Context, data: []const u8) !void {
        var backoff: u32 = self.options.initial_backoff_ms;
        var attempts: u8 = 0;

        while (attempts <= self.options.max_retries) : (attempts += 1) {
            // Try to connect if not connected
            self.connect() catch {
                if (attempts < self.options.max_retries) {
                    std.Thread.sleep(@as(u64, backoff) * std.time.ns_per_ms);
                    backoff = @min(backoff * 2, self.options.max_backoff_ms);
                    continue;
                }
                return error.ConnectionFailed;
            };

            // Try to write
            if (self.stream) |s| {
                _ = s.write(data) catch {
                    self.disconnect();
                    if (attempts < self.options.max_retries) {
                        std.Thread.sleep(@as(u64, backoff) * std.time.ns_per_ms);
                        backoff = @min(backoff * 2, self.options.max_backoff_ms);
                        continue;
                    }
                    return error.WriteFailed;
                };

                self.consecutive_failures = 0;
                metrics.global.addBytesWritten(data.len);
                return;
            }
        }

        self.consecutive_failures += 1;
        return error.WriteFailed;
    }
};

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    if (!rec.level.atLeast(ctx.level)) return;

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    // Format record as JSON line
    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Use a fixed buffer allocator for the encoder's state stack
    var stack_buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&stack_buf);

    var enc = json.streamingEncoder(fba.allocator(), writer, .{});
    defer enc.deinit();

    enc.beginObject() catch return error.WriteFailed;

    // time
    var ts_buf: [27]u8 = undefined;
    rfc3339.formatTimestamp(&ts_buf, rec.time_utc_us);
    enc.writeKey("time") catch return error.WriteFailed;
    enc.writeString(&ts_buf) catch return error.WriteFailed;

    // level
    enc.writeKey("level") catch return error.WriteFailed;
    enc.writeString(rec.level.asText()) catch return error.WriteFailed;

    // msg
    enc.writeKey("msg") catch return error.WriteFailed;
    enc.writeString(rec.message) catch return error.WriteFailed;

    // logger
    if (rec.logger.len > 0) {
        enc.writeKey("logger") catch return error.WriteFailed;
        enc.writeString(rec.logger) catch return error.WriteFailed;
    }

    enc.endObject() catch return error.WriteFailed;
    writer.writeByte('\n') catch return error.WriteFailed;

    ctx.writeWithRetry(fbs.getWritten()) catch |err| {
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
    ctx.level = level;
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
