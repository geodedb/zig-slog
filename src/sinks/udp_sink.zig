// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! UDP sink - sends log records over UDP.
//!
//! Features:
//! - Connectionless (fire and forget)
//! - Best-effort delivery (no retries by default)
//! - Low latency

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

/// UDP sink options.
pub const UdpOptions = struct {
    host: []const u8,
    port: u16,
    max_packet_size: usize = 65507, // Max UDP payload
};

/// UDP sink context.
pub const Context = struct {
    options: UdpOptions,
    socket: ?std.posix.fd_t,
    dest_addr: std.Io.net.IpAddress,
    level: std.atomic.Value(i32),
    clock: Clock,
    mutex: std.Io.Mutex,

    pub fn init(options: UdpOptions, level: Level, clock: Clock) !Context {
        // Parse destination address
        const dest_addr = std.Io.net.IpAddress.parseIp4(options.host, options.port) catch blk: {
            break :blk std.Io.net.IpAddress.parseIp6(options.host, options.port) catch {
                return error.InvalidAddress;
            };
        };

        // Create UDP socket via Io.net connect with dgram mode
        const io = std.Io.Threaded.global_single_threaded.io();
        const stream = dest_addr.connect(io, .{ .mode = .dgram }) catch return error.SocketError;

        return .{
            .options = options,
            .socket = stream.socket.handle,
            .dest_addr = dest_addr,
            .level = std.atomic.Value(i32).init(@intFromEnum(level)),
            .clock = clock,
            .mutex = std.Io.Mutex.init,
        };
    }

    pub fn deinit(self: *Context) void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        if (self.socket) |s| {
            _ = std.os.linux.close(s);
            self.socket = null;
        }
    }

    fn send(self: *Context, data: []const u8) !void {
        if (self.socket) |sock| {
            // If the record exceeds max_packet_size, drop it rather than
            // sending a truncated (and therefore malformed) JSON payload.
            if (data.len > self.options.max_packet_size) {
                metrics.global.incDropped(1);
                return;
            }
            const rc = std.os.linux.sendto(sock, data.ptr, data.len, 0, @ptrCast(&self.dest_addr), @sizeOf(@TypeOf(self.dest_addr)));
            if (rc > std.math.maxInt(isize)) {
                return error.WriteFailed;
            }
            metrics.global.addBytesWritten(data.len);
        }
    }
};

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    const current_level: Level = @enumFromInt(ctx.level.load(.acquire));
    if (!rec.level.atLeast(current_level)) return;

    // Format record as JSON OUTSIDE the mutex
    var buf: [8192]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    writeJsonRecord(&fbs, rec, "") catch return error.WriteFailed;

    const output = fbs.buffered();

    // Lock only for the network send
    ctx.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer ctx.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    ctx.send(output) catch {
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
