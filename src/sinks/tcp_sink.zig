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
const Value = @import("../value.zig").Value;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const Clock = @import("../internal/clock.zig").Clock;
const rfc3339 = @import("../fmt/rfc3339.zig");
const redact = @import("../util/redact.zig");
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
            .level = level,
            .clock = clock,
            .mutex = .{},
            .consecutive_failures = 0,
            .circuit_open_until = 0,
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
            self.applySocketTimeouts();
            return;
        };

        self.stream = std.net.tcpConnectToAddress(address) catch return error.ConnectionFailed;
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
            std.posix.setsockopt(s.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&timeval)) catch {};
            std.posix.setsockopt(s.handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&timeval)) catch {};
        }
    }

    fn disconnect(self: *Context) void {
        if (self.stream) |s| {
            s.close();
            self.stream = null;
        }
    }

    fn writeWithRetry(self: *Context, data: []const u8) !void {
        // Circuit breaker: fast-fail during cooldown period
        const now = std.time.milliTimestamp();
        if (self.consecutive_failures >= circuit_breaker_threshold and now < self.circuit_open_until) {
            return error.WriteFailed;
        }

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
                self.circuit_open_until = 0;
                metrics.global.addBytesWritten(data.len);
                return;
            }
        }

        self.consecutive_failures += 1;
        if (self.consecutive_failures >= circuit_breaker_threshold) {
            self.circuit_open_until = std.time.milliTimestamp() + circuit_cooldown_ms;
        }
        return error.WriteFailed;
    }
};

/// Write an attribute value as JSON.
fn writeJsonValue(enc: anytype, value: Value) !void {
    switch (value) {
        .str => |s| enc.writeString(s) catch return error.WriteFailed,
        .i64 => |i| enc.writeInt(i) catch return error.WriteFailed,
        .u64 => |u| enc.writeInt(u) catch return error.WriteFailed,
        .f64 => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                enc.writeNull() catch return error.WriteFailed;
            } else {
                enc.writeFloat(f) catch return error.WriteFailed;
            }
        },
        .bool => |b| enc.writeBool(b) catch return error.WriteFailed,
        .secret => enc.writeString(redact.REDACTED) catch return error.WriteFailed,
        .err => |e| {
            const raw: u16 = @intFromError(e);
            if (raw == 0) {
                enc.writeString("error(0)") catch return error.WriteFailed;
            } else {
                enc.writeString(@errorName(e)) catch return error.WriteFailed;
            }
        },
        .bytes => |bytes| {
            var hex_buf: [512]u8 = undefined;
            var hex_len: usize = 0;
            const hex_chars = "0123456789abcdef";
            for (bytes) |byte| {
                if (hex_len + 2 > hex_buf.len) break;
                hex_buf[hex_len] = hex_chars[byte >> 4];
                hex_buf[hex_len + 1] = hex_chars[byte & 0x0f];
                hex_len += 2;
            }
            enc.writeString(hex_buf[0..hex_len]) catch return error.WriteFailed;
        },
        .marshaler => enc.writeNull() catch return error.WriteFailed,
    }
}

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    if (!rec.level.atLeast(ctx.level)) return;

    // Format record as JSON line OUTSIDE the mutex
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

    // attrs
    for (rec.attrs) |attr| {
        enc.writeKey(attr.key) catch return error.WriteFailed;
        if (redact.isSensitiveKey(attr.key)) {
            enc.writeString(redact.REDACTED) catch return error.WriteFailed;
        } else {
            writeJsonValue(&enc, attr.value) catch return error.WriteFailed;
        }
    }

    enc.endObject() catch return error.WriteFailed;
    writer.writeByte('\n') catch return error.WriteFailed;

    const output = fbs.getWritten();

    // Lock only for the network write
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

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
