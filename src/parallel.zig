// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Parallel slog operations using thread-pool submitBatch/WaitGroup.
//!
//! Provides high-performance parallel implementations for logging
//! operations including batch record formatting, multi-handler dispatch,
//! and parallel sink writes.
//!
//! ## Overview
//!
//! This module enables parallel processing of logging operations using
//! the thread-pool library. Ideal for high-throughput logging systems
//! that need to format and dispatch many log records simultaneously.
//!
//! ## Build Configuration
//!
//! Enable: `-Denable_tp=true` (default)
//! Disable: `-Denable_tp=false`
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
const tp = @import("thread_pool");

// ============================================================================
// Global Thread Pool
// ============================================================================

var global_pool: ?tp.ThreadPool = null;
/// Atomic flag for the fast-path of the double-checked locking pattern.
/// Set to true after global_pool has been fully initialized.
var pool_initialized: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var pool_mutex: std.Io.Mutex = std.Io.Mutex.init;

/// Explicitly initialize the global thread pool with a given allocator
/// and configuration. If the pool is already initialized, this is a no-op.
///
/// Call this during application startup to control the allocator and thread
/// count. If not called, `getPool()` will lazily initialize with
/// `page_allocator` and default configuration.
pub fn initPool(allocator: std.mem.Allocator, config: tp.Config) void {
    pool_mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer pool_mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    if (global_pool == null) {
        global_pool = tp.ThreadPool.init(allocator, config) catch @panic("thread-pool init failed");
        pool_initialized.store(true, .release);
    }
}

pub fn getPool() *tp.ThreadPool {
    // Fast path: atomic load avoids the mutex when already initialized.
    if (pool_initialized.load(.acquire)) {
        return &global_pool.?;
    }

    // Slow path: acquire mutex and double-check.
    pool_mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer pool_mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    if (global_pool == null) {
        global_pool = tp.ThreadPool.init(std.heap.page_allocator, .{}) catch @panic("thread-pool init failed");
        pool_initialized.store(true, .release);
    }
    return &global_pool.?;
}

pub fn deinitPool() void {
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

const MAX_CHUNKS = 64;

/// Per-chunk context for parallel record formatting.
const RecordFormatChunk = struct {
    inputs: []const RecordInput,
    buffers: [][]u8,
    results: []FormattedRecord,
    formatter: RecordFormatter,
};

fn recordFormatChunkTask(ctx_ptr: *anyopaque, _: *tp.TaskContext) void {
    const chunk: *RecordFormatChunk = @ptrCast(@alignCast(ctx_ptr));
    for (chunk.inputs, 0..) |input, i| {
        chunk.results[i] = chunk.formatter(input, chunk.buffers[i]);
    }
}

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

    if (inputs.len < 8) {
        for (inputs, 0..) |input, i| {
            results[i] = formatter(input, buffers[i]);
        }
        return;
    }

    const n_chunks = @min(inputs.len, MAX_CHUNKS);
    var chunks: [MAX_CHUNKS]RecordFormatChunk = undefined;
    var batch: [MAX_CHUNKS]tp.BatchTask = undefined;

    const chunk_size = inputs.len / n_chunks;
    var offset: usize = 0;
    var n: usize = 0;
    while (n < n_chunks) : (n += 1) {
        const end = if (n == n_chunks - 1) inputs.len else offset + chunk_size;
        chunks[n] = .{
            .inputs = inputs[offset..end],
            .buffers = buffers[offset..end],
            .results = results[offset..end],
            .formatter = formatter,
        };
        batch[n] = .{ .task_fn = recordFormatChunkTask, .ctx = @ptrCast(&chunks[n]) };
        offset = end;
    }

    const pool = getPool();
    var wg = pool.waitGroup();
    _ = pool.submitBatch(batch[0..n], .{ .wait_group = &wg }) catch {
        // Fall back to sequential on error
        for (inputs, 0..) |input, i| {
            results[i] = formatter(input, buffers[i]);
        }
        return;
    };
    wg.wait();
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

/// Per-chunk context for parallel handler dispatch.
const HandlerDispatchChunk = struct {
    handlers: []const HandlerTarget,
    record_data: []const u8,
    results: []DispatchResult,
};

fn handlerDispatchChunkTask(ctx_ptr: *anyopaque, _: *tp.TaskContext) void {
    const chunk: *HandlerDispatchChunk = @ptrCast(@alignCast(ctx_ptr));
    for (chunk.handlers, 0..) |handler, i| {
        chunk.results[i] = handler.handler_fn(handler.handler_ptr, chunk.record_data);
    }
}

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

    if (handlers.len < 2) {
        for (handlers, 0..) |handler, i| {
            results[i] = handler.handler_fn(handler.handler_ptr, record_data);
        }
        return;
    }

    const n_chunks = @min(handlers.len, MAX_CHUNKS);
    var chunks: [MAX_CHUNKS]HandlerDispatchChunk = undefined;
    var batch: [MAX_CHUNKS]tp.BatchTask = undefined;

    const chunk_size = handlers.len / n_chunks;
    var offset: usize = 0;
    var n: usize = 0;
    while (n < n_chunks) : (n += 1) {
        const end = if (n == n_chunks - 1) handlers.len else offset + chunk_size;
        chunks[n] = .{
            .handlers = handlers[offset..end],
            .record_data = record_data,
            .results = results[offset..end],
        };
        batch[n] = .{ .task_fn = handlerDispatchChunkTask, .ctx = @ptrCast(&chunks[n]) };
        offset = end;
    }

    const pool = getPool();
    var wg = pool.waitGroup();
    _ = pool.submitBatch(batch[0..n], .{ .wait_group = &wg }) catch {
        for (handlers, 0..) |handler, i| {
            results[i] = handler.handler_fn(handler.handler_ptr, record_data);
        }
        return;
    };
    wg.wait();
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

/// Per-chunk context for parallel sink writes.
const SinkWriteChunk = struct {
    inputs: []const WriteInput,
    results: []WriteResult,
    writer: SinkWriter,
};

fn sinkWriteChunkTask(ctx_ptr: *anyopaque, _: *tp.TaskContext) void {
    const chunk: *SinkWriteChunk = @ptrCast(@alignCast(ctx_ptr));
    for (chunk.inputs, 0..) |input, i| {
        chunk.results[i] = chunk.writer(input.sink_ptr, input.data, input.flush);
    }
}

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

    if (inputs.len < 4) {
        for (inputs, 0..) |input, i| {
            results[i] = writer(input.sink_ptr, input.data, input.flush);
        }
        return;
    }

    const n_chunks = @min(inputs.len, MAX_CHUNKS);
    var chunks: [MAX_CHUNKS]SinkWriteChunk = undefined;
    var batch: [MAX_CHUNKS]tp.BatchTask = undefined;

    const chunk_size = inputs.len / n_chunks;
    var offset: usize = 0;
    var n: usize = 0;
    while (n < n_chunks) : (n += 1) {
        const end = if (n == n_chunks - 1) inputs.len else offset + chunk_size;
        chunks[n] = .{
            .inputs = inputs[offset..end],
            .results = results[offset..end],
            .writer = writer,
        };
        batch[n] = .{ .task_fn = sinkWriteChunkTask, .ctx = @ptrCast(&chunks[n]) };
        offset = end;
    }

    const pool = getPool();
    var wg = pool.waitGroup();
    _ = pool.submitBatch(batch[0..n], .{ .wait_group = &wg }) catch {
        for (inputs, 0..) |input, i| {
            results[i] = writer(input.sink_ptr, input.data, input.flush);
        }
        return;
    };
    wg.wait();
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

/// Per-chunk context for parallel flush.
const BatchFlushChunk = struct {
    targets: []const FlushTarget,
    results: []FlushResult,
    flusher: SinkFlusher,
};

fn batchFlushChunkTask(ctx_ptr: *anyopaque, _: *tp.TaskContext) void {
    const chunk: *BatchFlushChunk = @ptrCast(@alignCast(ctx_ptr));
    for (chunk.targets, 0..) |target, i| {
        chunk.results[i] = chunk.flusher(target.sink_ptr, target.timeout_ms);
    }
}

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

    if (targets.len < 2) {
        for (targets, 0..) |target, i| {
            results[i] = flusher(target.sink_ptr, target.timeout_ms);
        }
        return;
    }

    const n_chunks = @min(targets.len, MAX_CHUNKS);
    var chunks: [MAX_CHUNKS]BatchFlushChunk = undefined;
    var batch: [MAX_CHUNKS]tp.BatchTask = undefined;

    const chunk_size = targets.len / n_chunks;
    var offset: usize = 0;
    var n: usize = 0;
    while (n < n_chunks) : (n += 1) {
        const end = if (n == n_chunks - 1) targets.len else offset + chunk_size;
        chunks[n] = .{
            .targets = targets[offset..end],
            .results = results[offset..end],
            .flusher = flusher,
        };
        batch[n] = .{ .task_fn = batchFlushChunkTask, .ctx = @ptrCast(&chunks[n]) };
        offset = end;
    }

    const pool = getPool();
    var wg = pool.waitGroup();
    _ = pool.submitBatch(batch[0..n], .{ .wait_group = &wg }) catch {
        for (targets, 0..) |target, i| {
            results[i] = flusher(target.sink_ptr, target.timeout_ms);
        }
        return;
    };
    wg.wait();
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

/// Per-chunk context for parallel multi-handler dispatch.
const MultiHandlerChunk = struct {
    handlers: []const Handler,
    record: *const Record,
    results: []MultiHandlerResult,
};

fn multiHandlerChunkTask(ctx_ptr: *anyopaque, _: *tp.TaskContext) void {
    const chunk: *MultiHandlerChunk = @ptrCast(@alignCast(ctx_ptr));
    for (chunk.handlers, 0..) |h, i| {
        h.handle(chunk.record) catch |err| {
            chunk.results[i] = .{ .err = err };
            continue;
        };
        chunk.results[i] = .{ .err = null };
    }
}

/// Dispatch a record to multiple Handler instances in parallel.
///
/// Each handler receives the same Record pointer. Results are collected
/// per-handler so the caller can inspect individual errors.
///
/// Threshold: Uses parallel processing for 2+ handlers.
pub fn dispatchHandlers(
    handlers: []const Handler,
    record: *const Record,
    results: []MultiHandlerResult,
) void {
    std.debug.assert(handlers.len == results.len);

    if (handlers.len < 2) {
        for (handlers, 0..) |h, i| {
            h.handle(record) catch |err| {
                results[i] = .{ .err = err };
                continue;
            };
            results[i] = .{ .err = null };
        }
        return;
    }

    const n_chunks = @min(handlers.len, MAX_CHUNKS);
    var chunks: [MAX_CHUNKS]MultiHandlerChunk = undefined;
    var batch: [MAX_CHUNKS]tp.BatchTask = undefined;

    const chunk_size = handlers.len / n_chunks;
    var offset: usize = 0;
    var n: usize = 0;
    while (n < n_chunks) : (n += 1) {
        const end = if (n == n_chunks - 1) handlers.len else offset + chunk_size;
        chunks[n] = .{
            .handlers = handlers[offset..end],
            .record = record,
            .results = results[offset..end],
        };
        batch[n] = .{ .task_fn = multiHandlerChunkTask, .ctx = @ptrCast(&chunks[n]) };
        offset = end;
    }

    const pool = getPool();
    var wg = pool.waitGroup();
    _ = pool.submitBatch(batch[0..n], .{ .wait_group = &wg }) catch {
        for (handlers, 0..) |h, i| {
            h.handle(record) catch |err| {
                results[i] = .{ .err = err };
                continue;
            };
            results[i] = .{ .err = null };
        }
        return;
    };
    wg.wait();
}

// ============================================================================
// Parallel Multi-Handler Flush (Handler-native)
// ============================================================================

/// Result of flushing a single handler.
pub const MultiFlushResult = struct {
    err: ?HandlerError,
};

/// Per-chunk context for parallel multi-handler flush.
const MultiFlushChunk = struct {
    handlers: []const Handler,
    timeout_ms: u32,
    results: []MultiFlushResult,
};

fn multiFlushChunkTask(ctx_ptr: *anyopaque, _: *tp.TaskContext) void {
    const chunk: *MultiFlushChunk = @ptrCast(@alignCast(ctx_ptr));
    for (chunk.handlers, 0..) |h, i| {
        h.flush(chunk.timeout_ms) catch |err| {
            chunk.results[i] = .{ .err = err };
            continue;
        };
        chunk.results[i] = .{ .err = null };
    }
}

/// Flush multiple Handler instances in parallel.
///
/// Each handler is flushed independently. Results are collected
/// per-handler so the caller can inspect individual errors.
///
/// Threshold: Uses parallel processing for 2+ handlers.
pub fn flushHandlers(
    handlers: []const Handler,
    timeout_ms: u32,
    results: []MultiFlushResult,
) void {
    std.debug.assert(handlers.len == results.len);

    if (handlers.len < 2) {
        for (handlers, 0..) |h, i| {
            h.flush(timeout_ms) catch |err| {
                results[i] = .{ .err = err };
                continue;
            };
            results[i] = .{ .err = null };
        }
        return;
    }

    const n_chunks = @min(handlers.len, MAX_CHUNKS);
    var chunks: [MAX_CHUNKS]MultiFlushChunk = undefined;
    var batch: [MAX_CHUNKS]tp.BatchTask = undefined;

    const chunk_size = handlers.len / n_chunks;
    var offset: usize = 0;
    var n: usize = 0;
    while (n < n_chunks) : (n += 1) {
        const end = if (n == n_chunks - 1) handlers.len else offset + chunk_size;
        chunks[n] = .{
            .handlers = handlers[offset..end],
            .timeout_ms = timeout_ms,
            .results = results[offset..end],
        };
        batch[n] = .{ .task_fn = multiFlushChunkTask, .ctx = @ptrCast(&chunks[n]) };
        offset = end;
    }

    const pool = getPool();
    var wg = pool.waitGroup();
    _ = pool.submitBatch(batch[0..n], .{ .wait_group = &wg }) catch {
        for (handlers, 0..) |h, i| {
            h.flush(timeout_ms) catch |err| {
                results[i] = .{ .err = err };
                continue;
            };
            results[i] = .{ .err = null };
        }
        return;
    };
    wg.wait();
}

// ============================================================================
// Tests
// ============================================================================

test "parallel record format" {
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
