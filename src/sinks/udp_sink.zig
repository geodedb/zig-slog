// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! UDP sink - sends log records over UDP.
//!
//! Features:
//! - Connectionless (fire and forget)
//! - Best-effort delivery (no retries by default)
//! - Low latency

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

/// UDP sink options.
pub const UdpOptions = struct {
    host: []const u8,
    port: u16,
    max_packet_size: usize = 65507, // Max UDP payload
};

/// UDP sink context.
pub const Context = struct {
    options: UdpOptions,
    socket: ?std.posix.socket_t,
    dest_addr: std.net.Address,
    level: Level,
    clock: Clock,
    mutex: std.Thread.Mutex,

    pub fn init(options: UdpOptions, level: Level, clock: Clock) !Context {
        // Parse destination address
        const dest_addr = std.net.Address.parseIp4(options.host, options.port) catch blk: {
            break :blk std.net.Address.parseIp6(options.host, options.port) catch {
                return error.InvalidAddress;
            };
        };

        // Create UDP socket
        const sock = std.posix.socket(
            dest_addr.any.family,
            std.posix.SOCK.DGRAM,
            0,
        ) catch return error.SocketError;

        return .{
            .options = options,
            .socket = sock,
            .dest_addr = dest_addr,
            .level = level,
            .clock = clock,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Context) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.socket) |s| {
            std.posix.close(s);
            self.socket = null;
        }
    }

    fn send(self: *Context, data: []const u8) !void {
        if (self.socket) |sock| {
            // Truncate if needed
            const send_len = @min(data.len, self.options.max_packet_size);
            _ = std.posix.sendto(sock, data[0..send_len], 0, &self.dest_addr.any, self.dest_addr.getOsSockLen()) catch {
                return error.WriteFailed;
            };
            metrics.global.addBytesWritten(send_len);
        }
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

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    // Format record as JSON (no newline for UDP)
    var buf: [8192]u8 = undefined;
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

    ctx.send(fbs.getWritten()) catch {
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
    ctx.level = level;
}

fn flush(_: *anyopaque, _: u32) HandlerError!void {
    // UDP is connectionless, nothing to flush
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

/// Initialize a UDP sink handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

test "UdpSink init" {
    var ctx = Context.init(.{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system()) catch {
        // Socket creation may fail in test environment
        return;
    };
    defer ctx.deinit();

    const handler = init(&ctx);
    _ = handler;
}
