// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Parallel slog operations using spice heartbeat scheduling.
//!
//! Provides high-performance parallel implementations for logging
//! operations including batch record formatting, multi-handler dispatch,
//! and parallel sink writes.
//!
//! ## Overview
//!
//! This module enables parallel processing of logging operations using
//! the spice thread pool. Ideal for high-throughput logging systems
//! that need to format and dispatch many log records simultaneously.
//!
//! ## Build Configuration
//!
//! Enable: `-Dspice=true` (default)
//! Disable: `-Dspice=false`
//!
//! ## Usage Example
//!
//! ```zig
//! const parallel = @import("parallel.zig");
//!
//! // Format multiple log records in parallel
//! var inputs: [32]parallel.RecordInput = undefined;
//! var buffers: [32][]u8 = undefined;
//! var results: [32]parallel.FormattedRecord = undefined;
//!
//! // Initialize buffers...
//! for (&buffers) |*buf| {
//!     buf.* = allocator.alloc(u8, 1024) catch unreachable;
//! }
//!
//! parallel.parallelRecordFormat(&inputs, &buffers, &results, myFormatter);
//!
//! // Dispatch records to multiple handlers in parallel
//! var handlers: [4]parallel.Handler = undefined;
//! var dispatch_results: [4]parallel.DispatchResult = undefined;
//!
//! parallel.parallelHandlerDispatch(&handlers, &dispatch_results, record);
//! ```
//!
//! ## Performance Thresholds
//!
//! | Operation        | Threshold   | Sequential Below |
//! |------------------|-------------|------------------|
//! | Record Format    | 8 records   | Yes              |
//! | Handler Dispatch | 4 handlers  | Yes              |
//! | Sink Write       | 4 sinks     | Yes              |
//! | Batch Flush      | 8 batches   | Yes              |

const std = @import("std");

const spice = if (true) @import("spice") else struct {
    pub const ThreadPool = void;
    pub const Task = void;
    pub fn Future(comptime I: type, comptime O: type) type {
        _ = I;
        _ = O;
        return void;
    }
};

// ============================================================================
// Global Thread Pool
// ============================================================================

var global_pool: if (true) ?spice.ThreadPool else void = if (true) null else {};
/// Atomic flag for the fast-path of the double-checked locking pattern.
/// Set to true after global_pool has been fully initialized.
var pool_initialized: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var pool_mutex: std.Io.Mutex = std.Io.Mutex.init;

/// Explicitly initialize the global spice thread pool with a given allocator
/// and configuration. If the pool is already initialized, this is a no-op.
///
/// Call this during application startup to control the allocator and thread
/// count. If not called, `getPool()` will lazily initialize with
/// `page_allocator` and default configuration.
pub fn initPool(allocator: std.mem.Allocator, config: spice.ThreadPoolConfig) void {
    // spice always enabled when this module is compiled

    pool_mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer pool_mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    if (global_pool == null) {
        global_pool = spice.ThreadPool.init(allocator);
        global_pool.?.start(config);
        pool_initialized.store(true, .release);
    }
}

pub fn getPool() if (true) *spice.ThreadPool else void {
    // spice always enabled when this module is compiled

    // Fast path: atomic load avoids the mutex when already initialized.
    if (pool_initialized.load(.acquire)) {
        return &global_pool.?;
    }

    // Slow path: acquire mutex and double-check.
    pool_mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer pool_mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    if (global_pool == null) {
        global_pool = spice.ThreadPool.init(std.heap.page_allocator);
        global_pool.?.start(.{});
        pool_initialized.store(true, .release);
    }
    return &global_pool.?;
}

pub fn deinitPool() void {
    // spice always enabled when this module is compiled

    pool_mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer pool_mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    if (global_pool) |*pool| {
        pool.deinit();
        global_pool = null;
        pool_initialized.store(false, .release);
    }
}

// ============================================================================
// Parallel Record Formatting
// ============================================================================

/// Formatted output buffer
pub const FormattedRecord = struct {
    data: []u8,
    len: usize,
    success: bool,
};

/// Record input for formatting
pub const RecordInput = struct {
    time_utc_us: i128,
    level: u8,
    message: []const u8,
    logger: []const u8,
    attrs_json: []const u8,
};

/// Record formatter function type
pub const RecordFormatter = *const fn (input: RecordInput, buffer: []u8) FormattedRecord;

/// Context for parallel record formatting
pub const RecordFormatContext = struct {
    inputs: []const RecordInput,
    buffers: [][]u8,
    results: []FormattedRecord,
    formatter: RecordFormatter,
};

/// Format multiple log records in parallel.
///
/// Each record formatting is independent, enabling parallel
/// JSON/text serialization of log batches.
///
/// Parameters:
/// - inputs: Array of record inputs to format
/// - buffers: Array of output buffers for formatted records
/// - results: Array to store formatting results
/// - formatter: Function to format each record
///
/// Threshold: Uses parallel processing for 8+ records
pub fn parallelRecordFormat(
    inputs: []const RecordInput,
    buffers: [][]u8,
    results: []FormattedRecord,
    formatter: RecordFormatter,
) void {
    std.debug.assert(inputs.len == buffers.len);
    std.debug.assert(inputs.len == results.len);

    if (!true or inputs.len < 8) {
        for (inputs, 0..) |input, i| {
            results[i] = formatter(input, buffers[i]);
        }
        return;
    }

    const pool = getPool();
    const ctx = RecordFormatContext{
        .inputs = inputs,
        .buffers = buffers,
        .results = results,
        .formatter = formatter,
    };
    _ = pool.call(void, parallelRecordFormatTask, ctx);
}

fn parallelRecordFormatTask(t: *spice.Task, ctx: RecordFormatContext) void {
    const inputs = ctx.inputs;
    const buffers = ctx.buffers;
    const results = ctx.results;

    if (inputs.len < 4) {
        for (inputs, 0..) |input, i| {
            results[i] = ctx.formatter(input, buffers[i]);
        }
        return;
    }

    const mid = inputs.len / 2;
    const left_ctx = RecordFormatContext{
        .inputs = inputs[0..mid],
        .buffers = buffers[0..mid],
        .results = results[0..mid],
        .formatter = ctx.formatter,
    };
    const right_ctx = RecordFormatContext{
        .inputs = inputs[mid..],
        .buffers = buffers[mid..],
        .results = results[mid..],
        .formatter = ctx.formatter,
    };

    var fut = spice.Future(RecordFormatContext, void).init();
    fut.fork(t, parallelRecordFormatTask, right_ctx);

    t.call(void, parallelRecordFormatTask, left_ctx);
    if (fut.join(t) == null) {
        t.call(void, parallelRecordFormatTask, right_ctx);
    }
}

// ============================================================================
// Parallel Handler Dispatch
// ============================================================================

/// Handler dispatch result
pub const DispatchResult = struct {
    success: bool,
    handler_idx: usize,
    error_code: ?i32,
};

/// Handler context for dispatch
pub const HandlerTarget = struct {
    handler_ptr: *anyopaque,
    handler_fn: *const fn (ptr: *anyopaque, record_data: []const u8) DispatchResult,
};

/// Context for parallel handler dispatch
pub const HandlerDispatchContext = struct {
    handlers: []const HandlerTarget,
    record_data: []const u8,
    results: []DispatchResult,
};

/// Dispatch a single record to multiple handlers in parallel.
///
/// Each handler processes independently, enabling parallel
/// output to multiple sinks (console, file, network).
///
/// Parameters:
/// - handlers: Array of handler targets
/// - record_data: Formatted record data to dispatch
/// - results: Array to store dispatch results
///
/// Threshold: Uses parallel processing for 2+ handlers
pub fn parallelHandlerDispatch(
    handlers: []const HandlerTarget,
    record_data: []const u8,
    results: []DispatchResult,
) void {
    std.debug.assert(handlers.len == results.len);

    if (!true or handlers.len < 2) {
        for (handlers, 0..) |handler, i| {
            results[i] = handler.handler_fn(handler.handler_ptr, record_data);
        }
        return;
    }

    const pool = getPool();
    const ctx = HandlerDispatchContext{
        .handlers = handlers,
        .record_data = record_data,
        .results = results,
    };
    _ = pool.call(void, parallelHandlerDispatchTask, ctx);
}

fn parallelHandlerDispatchTask(t: *spice.Task, ctx: HandlerDispatchContext) void {
    const handlers = ctx.handlers;
    const results = ctx.results;

    if (handlers.len < 2) {
        for (handlers, 0..) |handler, i| {
            results[i] = handler.handler_fn(handler.handler_ptr, ctx.record_data);
        }
        return;
    }

    const mid = handlers.len / 2;
    const left_ctx = HandlerDispatchContext{
        .handlers = handlers[0..mid],
        .record_data = ctx.record_data,
        .results = results[0..mid],
    };
    const right_ctx = HandlerDispatchContext{
        .handlers = handlers[mid..],
        .record_data = ctx.record_data,
        .results = results[mid..],
    };

    var fut = spice.Future(HandlerDispatchContext, void).init();
    fut.fork(t, parallelHandlerDispatchTask, right_ctx);

    t.call(void, parallelHandlerDispatchTask, left_ctx);
    if (fut.join(t) == null) {
        t.call(void, parallelHandlerDispatchTask, right_ctx);
    }
}

// ============================================================================
// Parallel Sink Write
// ============================================================================

/// Write operation input
pub const WriteInput = struct {
    sink_ptr: *anyopaque,
    data: []const u8,
    flush: bool,
};

/// Write result
pub const WriteResult = struct {
    success: bool,
    bytes_written: usize,
    error_code: ?i32,
};

/// Sink writer function type
pub const SinkWriter = *const fn (sink_ptr: *anyopaque, data: []const u8, flush: bool) WriteResult;

/// Context for parallel sink writes
pub const SinkWriteContext = struct {
    inputs: []const WriteInput,
    results: []WriteResult,
    writer: SinkWriter,
};

/// Write formatted records to multiple sinks in parallel.
///
/// Each sink write is independent, enabling parallel I/O
/// to multiple output destinations.
///
/// Parameters:
/// - inputs: Array of write inputs
/// - results: Array to store write results
/// - writer: Function to perform each write
///
/// Threshold: Uses parallel processing for 4+ writes
pub fn parallelSinkWrite(
    inputs: []const WriteInput,
    results: []WriteResult,
    writer: SinkWriter,
) void {
    std.debug.assert(inputs.len == results.len);

    if (!true or inputs.len < 4) {
        for (inputs, 0..) |input, i| {
            results[i] = writer(input.sink_ptr, input.data, input.flush);
        }
        return;
    }

    const pool = getPool();
    const ctx = SinkWriteContext{
        .inputs = inputs,
        .results = results,
        .writer = writer,
    };
    _ = pool.call(void, parallelSinkWriteTask, ctx);
}

fn parallelSinkWriteTask(t: *spice.Task, ctx: SinkWriteContext) void {
    const inputs = ctx.inputs;
    const results = ctx.results;

    if (inputs.len < 2) {
        for (inputs, 0..) |input, i| {
            results[i] = ctx.writer(input.sink_ptr, input.data, input.flush);
        }
        return;
    }

    const mid = inputs.len / 2;
    const left_ctx = SinkWriteContext{
        .inputs = inputs[0..mid],
        .results = results[0..mid],
        .writer = ctx.writer,
    };
    const right_ctx = SinkWriteContext{
        .inputs = inputs[mid..],
        .results = results[mid..],
        .writer = ctx.writer,
    };

    var fut = spice.Future(SinkWriteContext, void).init();
    fut.fork(t, parallelSinkWriteTask, right_ctx);

    t.call(void, parallelSinkWriteTask, left_ctx);
    if (fut.join(t) == null) {
        t.call(void, parallelSinkWriteTask, right_ctx);
    }
}

// ============================================================================
// Parallel Batch Flush
// ============================================================================

/// Flush target
pub const FlushTarget = struct {
    sink_ptr: *anyopaque,
    timeout_ms: u32,
};

/// Flush result
pub const FlushResult = struct {
    success: bool,
    records_flushed: usize,
    timed_out: bool,
};

/// Sink flusher function type
pub const SinkFlusher = *const fn (sink_ptr: *anyopaque, timeout_ms: u32) FlushResult;

/// Context for parallel flush
pub const BatchFlushContext = struct {
    targets: []const FlushTarget,
    results: []FlushResult,
    flusher: SinkFlusher,
};

/// Flush multiple sinks in parallel.
///
/// Each sink flush is independent, enabling parallel
/// completion of pending writes across all sinks.
///
/// Parameters:
/// - targets: Array of flush targets
/// - results: Array to store flush results
/// - flusher: Function to flush each sink
///
/// Threshold: Uses parallel processing for 2+ sinks
pub fn parallelBatchFlush(
    targets: []const FlushTarget,
    results: []FlushResult,
    flusher: SinkFlusher,
) void {
    std.debug.assert(targets.len == results.len);

    if (!true or targets.len < 2) {
        for (targets, 0..) |target, i| {
            results[i] = flusher(target.sink_ptr, target.timeout_ms);
        }
        return;
    }

    const pool = getPool();
    const ctx = BatchFlushContext{
        .targets = targets,
        .results = results,
        .flusher = flusher,
    };
    _ = pool.call(void, parallelBatchFlushTask, ctx);
}

fn parallelBatchFlushTask(t: *spice.Task, ctx: BatchFlushContext) void {
    const targets = ctx.targets;
    const results = ctx.results;

    if (targets.len < 2) {
        for (targets, 0..) |target, i| {
            results[i] = ctx.flusher(target.sink_ptr, target.timeout_ms);
        }
        return;
    }

    const mid = targets.len / 2;
    const left_ctx = BatchFlushContext{
        .targets = targets[0..mid],
        .results = results[0..mid],
        .flusher = ctx.flusher,
    };
    const right_ctx = BatchFlushContext{
        .targets = targets[mid..],
        .results = results[mid..],
        .flusher = ctx.flusher,
    };

    var fut = spice.Future(BatchFlushContext, void).init();
    fut.fork(t, parallelBatchFlushTask, right_ctx);

    t.call(void, parallelBatchFlushTask, left_ctx);
    if (fut.join(t) == null) {
        t.call(void, parallelBatchFlushTask, right_ctx);
    }
}

// ============================================================================
// Parallel Multi-Handler Dispatch (Handler-native)
// ============================================================================

const Handler = @import("handler.zig").Handler;
const HandlerError = @import("handler.zig").HandlerError;
const Record = @import("record.zig").Record;

/// Result of dispatching a record to a single handler.
pub const MultiHandlerResult = struct {
    err: ?HandlerError,
};

/// Context for parallel multi-handler dispatch.
pub const MultiHandlerDispatchContext = struct {
    handlers: []const Handler,
    record: *const Record,
    results: []MultiHandlerResult,
};

/// Dispatch a record to multiple Handler instances in parallel.
///
/// Each handler receives the same Record pointer. Results are collected
/// per-handler so the caller can inspect individual errors.
///
/// Threshold: Uses parallel processing for 2+ handlers when spice is enabled.
pub fn dispatchHandlers(
    handlers: []const Handler,
    record: *const Record,
    results: []MultiHandlerResult,
) void {
    std.debug.assert(handlers.len == results.len);

    if (!true or handlers.len < 2) {
        for (handlers, 0..) |h, i| {
            h.handle(record) catch |err| {
                results[i] = .{ .err = err };
                continue;
            };
            results[i] = .{ .err = null };
        }
        return;
    }

    const pool = getPool();
    const ctx = MultiHandlerDispatchContext{
        .handlers = handlers,
        .record = record,
        .results = results,
    };
    _ = pool.call(void, multiHandlerDispatchTask, ctx);
}

fn multiHandlerDispatchTask(t: *spice.Task, ctx: MultiHandlerDispatchContext) void {
    const handlers = ctx.handlers;
    const results = ctx.results;

    if (handlers.len < 2) {
        for (handlers, 0..) |h, i| {
            h.handle(ctx.record) catch |err| {
                results[i] = .{ .err = err };
                continue;
            };
            results[i] = .{ .err = null };
        }
        return;
    }

    const mid = handlers.len / 2;
    const left_ctx = MultiHandlerDispatchContext{
        .handlers = handlers[0..mid],
        .record = ctx.record,
        .results = results[0..mid],
    };
    const right_ctx = MultiHandlerDispatchContext{
        .handlers = handlers[mid..],
        .record = ctx.record,
        .results = results[mid..],
    };

    var fut = spice.Future(MultiHandlerDispatchContext, void).init();
    fut.fork(t, multiHandlerDispatchTask, right_ctx);

    t.call(void, multiHandlerDispatchTask, left_ctx);
    if (fut.join(t) == null) {
        t.call(void, multiHandlerDispatchTask, right_ctx);
    }
}

// ============================================================================
// Parallel Multi-Handler Flush (Handler-native)
// ============================================================================

/// Result of flushing a single handler.
pub const MultiFlushResult = struct {
    err: ?HandlerError,
};

/// Context for parallel multi-handler flush.
pub const MultiFlushContext = struct {
    handlers: []const Handler,
    timeout_ms: u32,
    results: []MultiFlushResult,
};

/// Flush multiple Handler instances in parallel.
///
/// Each handler is flushed independently. Results are collected
/// per-handler so the caller can inspect individual errors.
///
/// Threshold: Uses parallel processing for 2+ handlers when spice is enabled.
pub fn flushHandlers(
    handlers: []const Handler,
    timeout_ms: u32,
    results: []MultiFlushResult,
) void {
    std.debug.assert(handlers.len == results.len);

    if (!true or handlers.len < 2) {
        for (handlers, 0..) |h, i| {
            h.flush(timeout_ms) catch |err| {
                results[i] = .{ .err = err };
                continue;
            };
            results[i] = .{ .err = null };
        }
        return;
    }

    const pool = getPool();
    const ctx = MultiFlushContext{
        .handlers = handlers,
        .timeout_ms = timeout_ms,
        .results = results,
    };
    _ = pool.call(void, multiFlushTask, ctx);
}

fn multiFlushTask(t: *spice.Task, ctx: MultiFlushContext) void {
    const handlers = ctx.handlers;
    const results = ctx.results;

    if (handlers.len < 2) {
        for (handlers, 0..) |h, i| {
            h.flush(ctx.timeout_ms) catch |err| {
                results[i] = .{ .err = err };
                continue;
            };
            results[i] = .{ .err = null };
        }
        return;
    }

    const mid = handlers.len / 2;
    const left_ctx = MultiFlushContext{
        .handlers = handlers[0..mid],
        .timeout_ms = ctx.timeout_ms,
        .results = results[0..mid],
    };
    const right_ctx = MultiFlushContext{
        .handlers = handlers[mid..],
        .timeout_ms = ctx.timeout_ms,
        .results = results[mid..],
    };

    var fut = spice.Future(MultiFlushContext, void).init();
    fut.fork(t, multiFlushTask, right_ctx);

    t.call(void, multiFlushTask, left_ctx);
    if (fut.join(t) == null) {
        t.call(void, multiFlushTask, right_ctx);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "parallel record format" {
    // spice always enabled when this module is compiled

    const testFormatter = struct {
        fn format(input: RecordInput, buffer: []u8) FormattedRecord {
            const len = @min(input.message.len, buffer.len);
            @memcpy(buffer[0..len], input.message[0..len]);
            return .{
                .data = buffer,
                .len = len,
                .success = true,
            };
        }
    }.format;

    var inputs: [16]RecordInput = undefined;
    var buffers: [16][256]u8 = undefined;
    var buffer_slices: [16][]u8 = undefined;
    var results: [16]FormattedRecord = undefined;

    for (&inputs, 0..) |*input, i| {
        _ = i;
        input.* = .{
            .time_utc_us = 0,
            .level = 2,
            .message = "test message",
            .logger = "test.logger",
            .attrs_json = "{}",
        };
    }

    for (&buffer_slices, &buffers) |*slice, *buf| {
        slice.* = buf;
    }

    parallelRecordFormat(&inputs, &buffer_slices, &results, testFormatter);

    for (results) |result| {
        try std.testing.expect(result.success);
        try std.testing.expect(result.len > 0);
    }
}

test "parallel handler dispatch" {
    // spice always enabled when this module is compiled

    const TestHandler = struct {
        fn dispatch(ptr: *anyopaque, record_data: []const u8) DispatchResult {
            _ = ptr;
            return .{
                .success = record_data.len > 0,
                .handler_idx = 0,
                .error_code = null,
            };
        }
    };

    var handlers: [4]HandlerTarget = undefined;
    var results: [4]DispatchResult = undefined;
    var dummy: u8 = 0;

    for (&handlers) |*h| {
        h.* = .{
            .handler_ptr = @ptrCast(&dummy),
            .handler_fn = TestHandler.dispatch,
        };
    }

    parallelHandlerDispatch(&handlers, "test record data", &results);

    for (results) |result| {
        try std.testing.expect(result.success);
    }
}

test "parallel handler dispatch - empty record" {
    // spice always enabled when this module is compiled

    const TestHandler = struct {
        fn dispatch(ptr: *anyopaque, record_data: []const u8) DispatchResult {
            _ = ptr;
            return .{
                .success = record_data.len > 0,
                .handler_idx = 0,
                .error_code = if (record_data.len == 0) @as(?i32, -1) else null,
            };
        }
    };

    var handlers: [4]HandlerTarget = undefined;
    var results: [4]DispatchResult = undefined;
    var dummy: u8 = 0;

    for (&handlers) |*h| {
        h.* = .{
            .handler_ptr = @ptrCast(&dummy),
            .handler_fn = TestHandler.dispatch,
        };
    }

    parallelHandlerDispatch(&handlers, "", &results); // Empty

    for (results) |result| {
        try std.testing.expect(!result.success);
    }
}

test "parallel sink write" {
    // spice always enabled when this module is compiled

    const testWriter = struct {
        fn write(sink_ptr: *anyopaque, data: []const u8, flush: bool) WriteResult {
            _ = sink_ptr;
            _ = flush;
            return .{
                .success = data.len > 0,
                .bytes_written = data.len,
                .error_code = null,
            };
        }
    }.write;

    var inputs: [8]WriteInput = undefined;
    var results: [8]WriteResult = undefined;
    var dummy: u8 = 0;

    for (&inputs) |*input| {
        input.* = .{
            .sink_ptr = @ptrCast(&dummy),
            .data = "log message here",
            .flush = false,
        };
    }

    parallelSinkWrite(&inputs, &results, testWriter);

    for (results) |result| {
        try std.testing.expect(result.success);
        try std.testing.expect(result.bytes_written > 0);
    }
}

test "parallel sink write - with flush" {
    // spice always enabled when this module is compiled

    const testWriter = struct {
        fn write(sink_ptr: *anyopaque, data: []const u8, flush: bool) WriteResult {
            _ = sink_ptr;
            return .{
                .success = true,
                .bytes_written = data.len,
                .error_code = if (flush) null else null, // flush handled
            };
        }
    }.write;

    var inputs: [4]WriteInput = undefined;
    var results: [4]WriteResult = undefined;
    var dummy: u8 = 0;

    for (&inputs) |*input| {
        input.* = .{
            .sink_ptr = @ptrCast(&dummy),
            .data = "message",
            .flush = true,
        };
    }

    parallelSinkWrite(&inputs, &results, testWriter);

    for (results) |result| {
        try std.testing.expect(result.success);
    }
}

test "parallel batch flush" {
    // spice always enabled when this module is compiled

    const testFlusher = struct {
        fn flush(sink_ptr: *anyopaque, timeout_ms: u32) FlushResult {
            _ = sink_ptr;
            return .{
                .success = timeout_ms > 0,
                .records_flushed = 10,
                .timed_out = false,
            };
        }
    }.flush;

    var targets: [4]FlushTarget = undefined;
    var results: [4]FlushResult = undefined;
    var dummy: u8 = 0;

    for (&targets) |*target| {
        target.* = .{
            .sink_ptr = @ptrCast(&dummy),
            .timeout_ms = 5000,
        };
    }

    parallelBatchFlush(&targets, &results, testFlusher);

    for (results) |result| {
        try std.testing.expect(result.success);
        try std.testing.expect(!result.timed_out);
        try std.testing.expectEqual(@as(usize, 10), result.records_flushed);
    }
}

test "parallel batch flush - timeout" {
    // spice always enabled when this module is compiled

    const testFlusher = struct {
        fn flush(sink_ptr: *anyopaque, timeout_ms: u32) FlushResult {
            _ = sink_ptr;
            return .{
                .success = timeout_ms > 0,
                .records_flushed = 0,
                .timed_out = timeout_ms == 0,
            };
        }
    }.flush;

    var targets: [4]FlushTarget = undefined;
    var results: [4]FlushResult = undefined;
    var dummy: u8 = 0;

    for (&targets) |*target| {
        target.* = .{
            .sink_ptr = @ptrCast(&dummy),
            .timeout_ms = 0, // Zero timeout
        };
    }

    parallelBatchFlush(&targets, &results, testFlusher);

    for (results) |result| {
        try std.testing.expect(!result.success);
        try std.testing.expect(result.timed_out);
    }
}

test "parallel record format - below threshold" {
    const testFormatter = struct {
        fn format(input: RecordInput, buffer: []u8) FormattedRecord {
            const len = @min(input.message.len, buffer.len);
            @memcpy(buffer[0..len], input.message[0..len]);
            return .{
                .data = buffer,
                .len = len,
                .success = true,
            };
        }
    }.format;

    var inputs: [4]RecordInput = undefined; // Below 8 threshold
    var buffers: [4][256]u8 = undefined;
    var buffer_slices: [4][]u8 = undefined;
    var results: [4]FormattedRecord = undefined;

    for (&inputs) |*input| {
        input.* = .{
            .time_utc_us = 0,
            .level = 2,
            .message = "test",
            .logger = "test",
            .attrs_json = "{}",
        };
    }

    for (&buffer_slices, &buffers) |*slice, *buf| {
        slice.* = buf;
    }

    parallelRecordFormat(&inputs, &buffer_slices, &results, testFormatter);

    for (results) |result| {
        try std.testing.expect(result.success);
    }
}

// ============================================================================
// Handler-native dispatch / flush tests
// ============================================================================

const Level = @import("level.zig").Level;
const Attr = @import("value.zig").Attr;

/// A counting handler that records how many times handle() and flush() are called.
const CountingHandler = struct {
    handle_count: usize,
    flush_count: usize,
    fail_on_handle: bool,
    fail_on_flush: bool,

    fn init(fail_handle: bool, fail_flush: bool) CountingHandler {
        return .{
            .handle_count = 0,
            .flush_count = 0,
            .fail_on_handle = fail_handle,
            .fail_on_flush = fail_flush,
        };
    }

    fn handleFn(ctx_ptr: *anyopaque, _: *const Record) HandlerError!void {
        const self: *CountingHandler = @ptrCast(@alignCast(ctx_ptr));
        self.handle_count += 1;
        if (self.fail_on_handle) return error.WriteFailed;
    }

    fn flushFn(ctx_ptr: *anyopaque, _: u32) HandlerError!void {
        const self: *CountingHandler = @ptrCast(@alignCast(ctx_ptr));
        self.flush_count += 1;
        if (self.fail_on_flush) return error.FlushFailed;
    }

    fn withAttrsFn(ctx_ptr: *anyopaque, _: []const Attr) Handler {
        return .{ .ctx = ctx_ptr, .vtable = &counting_vtable };
    }

    fn withGroupFn(ctx_ptr: *anyopaque, _: []const u8) Handler {
        return .{ .ctx = ctx_ptr, .vtable = &counting_vtable };
    }

    fn setLevelFn(_: *anyopaque, _: Level) void {}

    const counting_vtable = @import("handler.zig").HandlerVTable{
        .handle = handleFn,
        .withAttrs = withAttrsFn,
        .withGroup = withGroupFn,
        .setLevel = setLevelFn,
        .flush = flushFn,
    };

    fn handler(self: *CountingHandler) Handler {
        return .{ .ctx = @ptrCast(self), .vtable = &counting_vtable };
    }
};

test "dispatchHandlers - all succeed" {
    var h1 = CountingHandler.init(false, false);
    var h2 = CountingHandler.init(false, false);
    var h3 = CountingHandler.init(false, false);

    const handlers = [_]Handler{ h1.handler(), h2.handler(), h3.handler() };
    var results: [3]MultiHandlerResult = undefined;

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "dispatch test",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    dispatchHandlers(&handlers, &rec, &results);

    for (results) |r| {
        try std.testing.expect(r.err == null);
    }
    try std.testing.expectEqual(@as(usize, 1), h1.handle_count);
    try std.testing.expectEqual(@as(usize, 1), h2.handle_count);
    try std.testing.expectEqual(@as(usize, 1), h3.handle_count);
}

test "dispatchHandlers - partial failure" {
    var h1 = CountingHandler.init(false, false);
    var h2 = CountingHandler.init(true, false); // fails
    var h3 = CountingHandler.init(false, false);

    const handlers = [_]Handler{ h1.handler(), h2.handler(), h3.handler() };
    var results: [3]MultiHandlerResult = undefined;

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "partial fail",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    dispatchHandlers(&handlers, &rec, &results);

    try std.testing.expect(results[0].err == null);
    try std.testing.expect(results[1].err != null);
    try std.testing.expect(results[2].err == null);
    // All handlers should still be called even if one fails
    try std.testing.expectEqual(@as(usize, 1), h1.handle_count);
    try std.testing.expectEqual(@as(usize, 1), h2.handle_count);
    try std.testing.expectEqual(@as(usize, 1), h3.handle_count);
}

test "dispatchHandlers - single handler (below threshold)" {
    var h1 = CountingHandler.init(false, false);

    const handlers = [_]Handler{h1.handler()};
    var results: [1]MultiHandlerResult = undefined;

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "single",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    dispatchHandlers(&handlers, &rec, &results);

    try std.testing.expect(results[0].err == null);
    try std.testing.expectEqual(@as(usize, 1), h1.handle_count);
}

test "flushHandlers - all succeed" {
    var h1 = CountingHandler.init(false, false);
    var h2 = CountingHandler.init(false, false);

    const handlers = [_]Handler{ h1.handler(), h2.handler() };
    var results: [2]MultiFlushResult = undefined;

    flushHandlers(&handlers, 5000, &results);

    for (results) |r| {
        try std.testing.expect(r.err == null);
    }
    try std.testing.expectEqual(@as(usize, 1), h1.flush_count);
    try std.testing.expectEqual(@as(usize, 1), h2.flush_count);
}

test "flushHandlers - partial failure" {
    var h1 = CountingHandler.init(false, false);
    var h2 = CountingHandler.init(false, true); // flush fails

    const handlers = [_]Handler{ h1.handler(), h2.handler() };
    var results: [2]MultiFlushResult = undefined;

    flushHandlers(&handlers, 5000, &results);

    try std.testing.expect(results[0].err == null);
    try std.testing.expect(results[1].err != null);
    try std.testing.expectEqual(@as(usize, 1), h1.flush_count);
    try std.testing.expectEqual(@as(usize, 1), h2.flush_count);
}

test "dispatchHandlers - empty list" {
    const handlers = [_]Handler{};
    var results: [0]MultiHandlerResult = undefined;

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "empty",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    dispatchHandlers(&handlers, &rec, &results);
    // No assertions needed -- just verifying no crash on empty input
}

test "flushHandlers - single handler (below threshold)" {
    var h1 = CountingHandler.init(false, false);

    const handlers = [_]Handler{h1.handler()};
    var results: [1]MultiFlushResult = undefined;

    flushHandlers(&handlers, 1000, &results);

    try std.testing.expect(results[0].err == null);
    try std.testing.expectEqual(@as(usize, 1), h1.flush_count);
}

test "flushHandlers - empty list" {
    const handlers = [_]Handler{};
    var results: [0]MultiFlushResult = undefined;

    flushHandlers(&handlers, 1000, &results);
}

test "dispatchHandlers - all fail" {
    var h1 = CountingHandler.init(true, false);
    var h2 = CountingHandler.init(true, false);

    const handlers = [_]Handler{ h1.handler(), h2.handler() };
    var results: [2]MultiHandlerResult = undefined;

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "all fail",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    dispatchHandlers(&handlers, &rec, &results);

    for (results) |r| {
        try std.testing.expect(r.err != null);
    }
    try std.testing.expectEqual(@as(usize, 1), h1.handle_count);
    try std.testing.expectEqual(@as(usize, 1), h2.handle_count);
}
