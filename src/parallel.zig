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
const build_options = @import("build_options");

const spice = if (build_options.enable_spice) @import("spice") else struct {
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

var global_pool: if (build_options.enable_spice) ?spice.ThreadPool else void = if (build_options.enable_spice) null else {};
var pool_mutex: std.Thread.Mutex = .{};

pub fn getPool() if (build_options.enable_spice) *spice.ThreadPool else void {
    if (!build_options.enable_spice) return;

    pool_mutex.lock();
    defer pool_mutex.unlock();

    if (global_pool == null) {
        global_pool = spice.ThreadPool.init(std.heap.page_allocator);
        global_pool.?.start(.{});
    }
    return &global_pool.?;
}

pub fn deinitPool() void {
    if (!build_options.enable_spice) return;

    pool_mutex.lock();
    defer pool_mutex.unlock();

    if (global_pool) |*pool| {
        pool.deinit();
        global_pool = null;
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

    if (!build_options.enable_spice or inputs.len < 8) {
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

    if (!build_options.enable_spice or handlers.len < 2) {
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

    if (!build_options.enable_spice or inputs.len < 4) {
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

    if (!build_options.enable_spice or targets.len < 2) {
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
// Tests
// ============================================================================

test "parallel record format" {
    if (!build_options.enable_spice) return error.SkipZigTest;

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
    if (!build_options.enable_spice) return error.SkipZigTest;

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
    if (!build_options.enable_spice) return error.SkipZigTest;

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
    if (!build_options.enable_spice) return error.SkipZigTest;

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
    if (!build_options.enable_spice) return error.SkipZigTest;

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
    if (!build_options.enable_spice) return error.SkipZigTest;

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
    if (!build_options.enable_spice) return error.SkipZigTest;

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
