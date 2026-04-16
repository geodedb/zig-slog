// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Async handler - buffers records and delivers to inner handler on background thread.
//!
//! Features:
//! - Bounded queue with configurable size
//! - Drop-oldest policy with metrics tracking
//! - Optional blocking mode with timeout
//! - Background thread for delivery
//!
//! ## Usage
//!
//! The Context must be initialized and started in two steps to avoid
//! dangling pointers. `init()` creates the context by value, and `start()`
//! spawns the background worker thread using the caller's stable pointer:
//!
//! ```zig
//! var ctx = try Context.init(allocator, options);
//! try ctx.start(); // spawns worker thread using &ctx (stable address)
//! defer ctx.deinit();
//! ```
//!
//! ## Attribute preservation
//!
//! All record attributes are preserved through the async queue. Values are
//! serialized to their string representation at enqueue time. See
//! `src/internal/queue.zig` for serialization details.

const std = @import("std");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const BoundedQueue = @import("../internal/queue.zig").BoundedQueue;
const QueuedRecord = @import("../internal/queue.zig").QueuedRecord;
const MAX_STORED_ATTRS = @import("../internal/queue.zig").MAX_STORED_ATTRS;
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
    level: std.atomic.Value(i32),
    running: std.atomic.Value(bool),
    thread: ?std.Thread,

    /// Initialize the async handler context. Does NOT start the background
    /// worker thread. Call `start()` after the Context has a stable address.
    pub fn init(allocator: std.mem.Allocator, options: AsyncOptions) !Context {
        return Context{
            .allocator = allocator,
            .inner = options.inner,
            .queue = try BoundedQueue(QueuedRecord).init(allocator, options.queue_size),
            .drop_oldest = options.drop_oldest,
            .block_timeout_ms = options.block_timeout_ms,
            .level = std.atomic.Value(i32).init(@intFromEnum(Level.info)),
            .running = std.atomic.Value(bool).init(true),
            .thread = null,
        };
    }

    /// Start the background worker thread. Must be called after the Context
    /// has been placed at its final address (e.g., on the caller's stack frame
    /// or heap). Calling `start()` on a moved Context would be undefined behavior.
    pub fn start(self: *Context) !void {
        // daemon: async log flusher — long-lived consumer of the log ring
        // buffer. Runs for the handler's lifetime. Not pool work — a pool
        // worker holding this loop would never return to the shared queue.
        self.thread = try std.Thread.spawn(.{}, workerThread, .{self});
    }

    pub fn deinit(self: *Context) void {
        // Signal shutdown
        self.running.store(false, .release);

        // Wake up worker thread
        self.queue.not_empty.signal(std.Io.Threaded.global_single_threaded.io());

        // Wait for thread
        if (self.thread) |t| {
            t.join();
        }

        self.queue.deinit(self.allocator);
    }

    /// Maximum records to drain per wake cycle (batch processing).
    const max_batch_size: usize = 32;

    fn workerThread(ctx: *Context) void {
        while (ctx.running.load(.acquire)) {
            // Wait for a record with timeout
            if (ctx.queue.popTimeout(100)) |qr| {
                processQueuedRecord(ctx, qr);

                // Batch drain: process additional queued records without
                // re-waiting, up to max_batch_size per wake cycle.
                var batch: usize = 1;
                while (batch < max_batch_size) : (batch += 1) {
                    if (ctx.queue.tryPop()) |batch_qr| {
                        processQueuedRecord(ctx, batch_qr);
                    } else break;
                }
            }
        }

        // Drain remaining records at shutdown
        while (ctx.queue.tryPop()) |qr| {
            processQueuedRecord(ctx, qr);
        }
    }

    /// Reconstruct a Record from QueuedRecord and deliver to inner handler.
    fn processQueuedRecord(ctx: *Context, qr: QueuedRecord) void {
        if (!qr.valid) return;

        var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
        const attrs = qr.attrs(&attr_buf);

        const rec = Record{
            .time_utc_us = qr.time_utc_us,
            .level = @enumFromInt(qr.level_int),
            .msg_id = qr.msgId(),
            .message = qr.message(),
            .logger = qr.logger(),
            .source_file = qr.sourceFile(),
            .source_line = qr.source_line,
            .attrs = attrs,
        };

        ctx.inner.handle(&rec) catch {
            metrics.global.incErrors();
        };
    }

    /// Enqueue a record for async delivery.
    /// Uses the queue's internal mutex for thread safety -- no external
    /// locking is needed. Drop tracking uses the queue's own dropped counter.
    pub fn enqueue(self: *Context, rec: *const Record) !void {
        const qr = QueuedRecord.fromRecord(rec);

        if (self.drop_oldest) {
            // Snapshot the dropped count before pushing so we can detect
            // if the queue itself dropped an item during this push.
            const before = self.queue.droppedCount();

            // pushDropOldest returns the queue length after the push,
            // eliminating the need for a separate len() call.
            const queue_len = self.queue.pushDropOldest(qr);

            const after = self.queue.droppedCount();
            if (after > before) {
                metrics.global.incDropped(after - before);
            }

            metrics.global.setQueueSize(queue_len);
        } else {
            // Blocking mode
            self.queue.pushBlocking(qr, self.block_timeout_ms) catch |err| {
                switch (err) {
                    error.Timeout, error.QueueFull => {
                        metrics.global.incDropped(1);
                        return error.BufferFull;
                    },
                    else => return err,
                }
            };

            metrics.global.setQueueSize(self.queue.len());
        }
    }

    /// Returns the total number of records dropped by the queue.
    pub fn droppedCount(self: *Context) usize {
        return self.queue.droppedCount();
    }
};

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    const current_level: Level = @enumFromInt(ctx.level.load(.acquire));
    if (!rec.level.atLeast(current_level)) return;

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
    ctx.level.store(@intFromEnum(level), .release);
}

/// Flush waits for the queue to drain using the queue's empty condition
/// variable, then flushes the inner handler.
fn flush(ctx_ptr: *anyopaque, timeout_ms: u32) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    // Wait for queue to drain using the CV-based waitEmpty.
    // If timeout_ms is 0, we still try a brief wait to allow in-flight items
    // to be processed.
    const wait_ms = if (timeout_ms == 0) 5000 else timeout_ms;
    if (!ctx.queue.waitEmpty(wait_ms)) {
        if (timeout_ms > 0) return error.Timeout;
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
pub fn getDroppedCount(handler: Handler) usize {
    const ctx: *Context = @ptrCast(@alignCast(handler.ctx));
    return ctx.droppedCount();
}

test "AsyncHandler basic" {
    const allocator = std.testing.allocator;

    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    const text_handler_mod = @import("text_handler.zig");
    var text_ctx = text_handler_mod.Context.init(&fbs, .info, @import("../internal/clock.zig").Clock.system());
    const inner = text_handler_mod.init(&text_ctx);

    var async_ctx = try Context.init(allocator, .{
        .inner = inner,
        .queue_size = 16,
        .drop_oldest = true,
    });
    try async_ctx.start();
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

    const output = fbs.buffered();
    try std.testing.expect(output.len > 0);
}

test "AsyncHandler preserves attributes through queue" {
    const allocator = std.testing.allocator;

    var buf: [8192]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    const text_handler_mod = @import("text_handler.zig");
    var text_ctx = text_handler_mod.Context.init(&fbs, .info, @import("../internal/clock.zig").Clock.system());
    const inner = text_handler_mod.init(&text_ctx);

    var async_ctx = try Context.init(allocator, .{
        .inner = inner,
        .queue_size = 16,
        .drop_oldest = true,
    });
    try async_ctx.start();
    defer async_ctx.deinit();

    const handler = init(&async_ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "attrs test",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("host", "localhost"),
            Attr.int("port", 8080),
            Attr.boolean("tls", true),
        },
    };

    try handler.handle(&rec);
    try handler.flush(5000);

    const output = fbs.buffered();
    // Verify all attributes appear in the output
    try std.testing.expect(std.mem.indexOf(u8, output, "host=localhost") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "port=8080") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "tls=true") != null);
}

test "AsyncHandler preserves i64 values through queue" {
    const allocator = std.testing.allocator;

    var buf: [8192]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    const text_handler_mod = @import("text_handler.zig");
    var text_ctx = text_handler_mod.Context.init(&fbs, .info, @import("../internal/clock.zig").Clock.system());
    const inner = text_handler_mod.init(&text_ctx);

    var async_ctx = try Context.init(allocator, .{
        .inner = inner,
        .queue_size = 16,
        .drop_oldest = true,
    });
    try async_ctx.start();
    defer async_ctx.deinit();

    const handler = init(&async_ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "i64 test",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.int("count", 42),
            Attr.int("negative", -100),
            Attr.int("zero", 0),
        },
    };

    try handler.handle(&rec);
    try handler.flush(5000);

    const output = fbs.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "count=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "negative=-100") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "zero=0") != null);
}

test "AsyncHandler redacts secrets in async output" {
    const allocator = std.testing.allocator;

    var buf: [8192]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    const text_handler_mod = @import("text_handler.zig");
    var text_ctx = text_handler_mod.Context.init(&fbs, .info, @import("../internal/clock.zig").Clock.system());
    const inner = text_handler_mod.init(&text_ctx);

    var async_ctx = try Context.init(allocator, .{
        .inner = inner,
        .queue_size = 16,
        .drop_oldest = true,
    });
    try async_ctx.start();
    defer async_ctx.deinit();

    const handler = init(&async_ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "secret test",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.secret("api_key", "super_secret_value"),
            Attr.string("user", "admin"),
        },
    };

    try handler.handle(&rec);
    try handler.flush(5000);

    const output = fbs.buffered();
    // The secret should be redacted, not present in output
    try std.testing.expect(std.mem.indexOf(u8, output, "super_secret_value") == null);
    // The key should still appear with the redacted marker
    try std.testing.expect(std.mem.indexOf(u8, output, "api_key=[REDACTED]") != null);
    // Non-secret attrs should still be present
    try std.testing.expect(std.mem.indexOf(u8, output, "user=admin") != null);
}
