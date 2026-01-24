// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Async handler - buffers records and delivers to inner handler on background thread.
//!
//! Features:
//! - Bounded queue with configurable size
//! - Drop-oldest policy with metrics tracking
//! - Optional blocking mode with timeout
//! - Background thread for delivery

const std = @import("std");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const BoundedQueue = @import("../internal/queue.zig").BoundedQueue;
const QueuedRecord = @import("../internal/queue.zig").QueuedRecord;
const metrics = @import("../metrics/metrics.zig");

/// Async handler options.
pub const AsyncOptions = struct {
    inner: Handler,
    queue_size: usize = 1024,
    drop_oldest: bool = true,
    block_timeout_ms: u32 = 0,
};

/// Async handler context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    inner: Handler,
    queue: BoundedQueue(QueuedRecord),
    drop_oldest: bool,
    block_timeout_ms: u32,
    level: Level,
    running: std.atomic.Value(bool),
    thread: ?std.Thread,
    mutex: std.Thread.Mutex,
    dropped_count: std.atomic.Value(u64),

    pub fn init(allocator: std.mem.Allocator, options: AsyncOptions) !Context {
        var ctx = Context{
            .allocator = allocator,
            .inner = options.inner,
            .queue = try BoundedQueue(QueuedRecord).init(allocator, options.queue_size),
            .drop_oldest = options.drop_oldest,
            .block_timeout_ms = options.block_timeout_ms,
            .level = .info,
            .running = std.atomic.Value(bool).init(true),
            .thread = null,
            .mutex = .{},
            .dropped_count = std.atomic.Value(u64).init(0),
        };

        // Start background thread
        ctx.thread = std.Thread.spawn(.{}, workerThread, .{&ctx}) catch null;

        return ctx;
    }

    pub fn deinit(self: *Context) void {
        // Signal shutdown
        self.running.store(false, .release);

        // Wake up worker thread
        self.queue.not_empty.signal();

        // Wait for thread
        if (self.thread) |t| {
            t.join();
        }

        self.queue.deinit(self.allocator);
    }

    fn workerThread(ctx: *Context) void {
        while (ctx.running.load(.acquire)) {
            // Try to get a record with timeout
            if (ctx.queue.popTimeout(100)) |qr| {
                if (qr.valid) {
                    // Reconstruct record and deliver
                    const rec = Record{
                        .time_utc_us = qr.time_utc_us,
                        .level = @enumFromInt(qr.level_int),
                        .msg_id = qr.msgId(),
                        .message = qr.message(),
                        .logger = qr.logger(),
                        .source_file = qr.sourceFile(),
                        .source_line = qr.source_line,
                        .attrs = &.{}, // Simplified
                    };

                    ctx.inner.handle(&rec) catch {
                        metrics.global.incErrors();
                    };
                }
            }
        }

        // Drain remaining records
        while (ctx.queue.tryPop()) |qr| {
            if (qr.valid) {
                const rec = Record{
                    .time_utc_us = qr.time_utc_us,
                    .level = @enumFromInt(qr.level_int),
                    .msg_id = qr.msgId(),
                    .message = qr.message(),
                    .logger = qr.logger(),
                    .source_file = qr.sourceFile(),
                    .source_line = qr.source_line,
                    .attrs = &.{},
                };

                ctx.inner.handle(&rec) catch {
                    metrics.global.incErrors();
                };
            }
        }
    }

    pub fn enqueue(self: *Context, rec: *const Record) !void {
        const qr = QueuedRecord.fromRecord(rec);

        if (self.drop_oldest) {
            // Check if we'll drop
            self.mutex.lock();
            const was_full = self.queue.len() >= self.queue.buffer.len;
            self.mutex.unlock();

            self.queue.pushDropOldest(qr);

            if (was_full) {
                _ = self.dropped_count.fetchAdd(1, .monotonic);
                metrics.global.incDropped(1);
            }
        } else {
            // Blocking mode
            self.queue.pushBlocking(qr, self.block_timeout_ms) catch |err| {
                switch (err) {
                    error.Timeout, error.QueueFull => {
                        _ = self.dropped_count.fetchAdd(1, .monotonic);
                        metrics.global.incDropped(1);
                        return error.BufferFull;
                    },
                    else => return err,
                }
            };
        }

        metrics.global.setQueueSize(self.queue.len());
    }

    pub fn droppedCount(self: *Context) u64 {
        return self.dropped_count.load(.monotonic);
    }
};

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    if (!rec.level.atLeast(ctx.level)) return;

    ctx.enqueue(rec) catch |err| {
        return switch (err) {
            error.BufferFull => error.BufferFull,
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

fn flush(ctx_ptr: *anyopaque, timeout_ms: u32) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    // Wait for queue to drain
    const start = std.time.milliTimestamp();
    while (ctx.queue.len() > 0) {
        if (timeout_ms > 0) {
            const elapsed = std.time.milliTimestamp() - start;
            if (elapsed >= timeout_ms) return error.Timeout;
        }
        std.time.sleep(1 * std.time.ns_per_ms);
    }

    // Flush inner handler
    try ctx.inner.flush(timeout_ms);
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

/// Initialize an async handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

/// Get dropped count from async handler.
pub fn getDroppedCount(handler: Handler) u64 {
    const ctx: *Context = @ptrCast(@alignCast(handler.ctx));
    return ctx.droppedCount();
}

test "AsyncHandler basic" {
    const allocator = std.testing.allocator;

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const text_handler_mod = @import("text_handler.zig");
    var text_ctx = text_handler_mod.Context.init(fbs.writer().any(), .info, @import("../internal/clock.zig").Clock.system());
    const inner = text_handler_mod.init(&text_ctx);

    var async_ctx = try Context.init(allocator, .{
        .inner = inner,
        .queue_size = 16,
        .drop_oldest = true,
    });
    defer async_ctx.deinit();

    const handler = init(&async_ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "async test",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    try handler.flush(5000);

    const output = fbs.getWritten();
    try std.testing.expect(output.len > 0);
}
