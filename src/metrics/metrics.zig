// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Metrics collection and export for slogz.
//!
//! Provides counters for logs emitted, dropped, and handler errors.
//! Supports Prometheus-style text export.

const std = @import("std");
const builtin = @import("builtin");

// Use usize for atomic counters to ensure native atomic support on all architectures.
// On 32-bit platforms (ARM32), 64-bit atomics aren't natively supported, so we use
// usize which maps to the native pointer width (32-bit or 64-bit).
const CounterType = usize;
const AtomicCounter = std.atomic.Value(CounterType);

/// Global metrics instance.
pub var global: Metrics = .{};

/// Reset global metrics (for testing).
pub fn reset() void {
    global = .{};
}

/// Cache line size used to pad atomic counters, preventing false sharing
/// when multiple threads update adjacent counters concurrently.
const cache_line = 64;

/// A cache-line-aligned atomic counter that occupies exactly one cache line,
/// preventing false sharing between adjacent counters in the Metrics struct.
const PaddedCounter = struct {
    value: AtomicCounter align(cache_line) = AtomicCounter.init(0),
};

/// Metrics counters for logging operations.
///
/// Each counter is padded to a separate cache line (64 bytes) so that
/// concurrent increments on different counters do not cause false sharing.
pub const Metrics = struct {
    /// Total number of log records emitted.
    logs_emitted_total: PaddedCounter = .{},
    /// Total number of log records dropped (e.g., queue full).
    logs_dropped_total: PaddedCounter = .{},
    /// Total number of handler errors.
    handler_errors_total: PaddedCounter = .{},
    /// Total bytes written.
    bytes_written_total: PaddedCounter = .{},
    /// Records currently in async queue.
    queue_size: PaddedCounter = .{},
    /// Number of file rotations.
    rotations_total: PaddedCounter = .{},
    /// Number of network reconnections.
    reconnections_total: PaddedCounter = .{},

    /// Increment logs emitted counter.
    pub fn incEmitted(self: *Metrics) void {
        _ = self.logs_emitted_total.value.fetchAdd(1, .monotonic);
    }

    /// Increment logs dropped counter.
    pub fn incDropped(self: *Metrics, count: CounterType) void {
        _ = self.logs_dropped_total.value.fetchAdd(count, .monotonic);
    }

    /// Increment handler errors counter.
    pub fn incErrors(self: *Metrics) void {
        _ = self.handler_errors_total.value.fetchAdd(1, .monotonic);
    }

    /// Add bytes written.
    pub fn addBytesWritten(self: *Metrics, bytes: CounterType) void {
        _ = self.bytes_written_total.value.fetchAdd(bytes, .monotonic);
    }

    /// Set queue size.
    pub fn setQueueSize(self: *Metrics, size: CounterType) void {
        self.queue_size.value.store(size, .monotonic);
    }

    /// Increment rotations counter.
    pub fn incRotations(self: *Metrics) void {
        _ = self.rotations_total.value.fetchAdd(1, .monotonic);
    }

    /// Increment reconnections counter.
    pub fn incReconnections(self: *Metrics) void {
        _ = self.reconnections_total.value.fetchAdd(1, .monotonic);
    }

    /// Get current values.
    pub fn snapshot(self: *const Metrics) MetricsSnapshot {
        return .{
            .logs_emitted_total = self.logs_emitted_total.value.load(.monotonic),
            .logs_dropped_total = self.logs_dropped_total.value.load(.monotonic),
            .handler_errors_total = self.handler_errors_total.value.load(.monotonic),
            .bytes_written_total = self.bytes_written_total.value.load(.monotonic),
            .queue_size = self.queue_size.value.load(.monotonic),
            .rotations_total = self.rotations_total.value.load(.monotonic),
            .reconnections_total = self.reconnections_total.value.load(.monotonic),
        };
    }

    /// Render metrics in Prometheus text format.
    pub fn renderPrometheus(self: *const Metrics, buf: []u8) []const u8 {
        const snap = self.snapshot();
        var fbs = std.io.fixedBufferStream(buf);
        const writer = fbs.writer();

        writer.print(
            \\# HELP slogz_logs_emitted_total Total number of log records emitted.
            \\# TYPE slogz_logs_emitted_total counter
            \\slogz_logs_emitted_total {d}
            \\# HELP slogz_logs_dropped_total Total number of log records dropped.
            \\# TYPE slogz_logs_dropped_total counter
            \\slogz_logs_dropped_total {d}
            \\# HELP slogz_handler_errors_total Total number of handler errors.
            \\# TYPE slogz_handler_errors_total counter
            \\slogz_handler_errors_total {d}
            \\# HELP slogz_bytes_written_total Total bytes written.
            \\# TYPE slogz_bytes_written_total counter
            \\slogz_bytes_written_total {d}
            \\# HELP slogz_queue_size Current async queue size.
            \\# TYPE slogz_queue_size gauge
            \\slogz_queue_size {d}
            \\# HELP slogz_rotations_total Total file rotations.
            \\# TYPE slogz_rotations_total counter
            \\slogz_rotations_total {d}
            \\# HELP slogz_reconnections_total Total network reconnections.
            \\# TYPE slogz_reconnections_total counter
            \\slogz_reconnections_total {d}
            \\
        , .{
            snap.logs_emitted_total,
            snap.logs_dropped_total,
            snap.handler_errors_total,
            snap.bytes_written_total,
            snap.queue_size,
            snap.rotations_total,
            snap.reconnections_total,
        }) catch {};

        return fbs.getWritten();
    }
};

/// Immutable snapshot of metrics values.
pub const MetricsSnapshot = struct {
    logs_emitted_total: CounterType,
    logs_dropped_total: CounterType,
    handler_errors_total: CounterType,
    bytes_written_total: CounterType,
    queue_size: CounterType,
    rotations_total: CounterType,
    reconnections_total: CounterType,
};

test "Metrics basic operations" {
    var m = Metrics{};

    m.incEmitted();
    m.incEmitted();
    m.incDropped(3);
    m.incErrors();

    const snap = m.snapshot();
    try std.testing.expectEqual(@as(CounterType, 2), snap.logs_emitted_total);
    try std.testing.expectEqual(@as(CounterType, 3), snap.logs_dropped_total);
    try std.testing.expectEqual(@as(CounterType, 1), snap.handler_errors_total);
}

test "Metrics.renderPrometheus" {
    var m = Metrics{};
    m.incEmitted();
    m.incEmitted();
    m.incEmitted();

    var buf: [2048]u8 = undefined;
    const output = m.renderPrometheus(&buf);

    try std.testing.expect(std.mem.indexOf(u8, output, "slogz_logs_emitted_total 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "slogz_logs_dropped_total 0") != null);
}

test "Metrics counters are cache-line aligned to prevent false sharing" {
    // Each PaddedCounter's value field should be aligned to 64 bytes.
    var m = Metrics{};
    const base = @intFromPtr(&m);

    const emitted_addr = @intFromPtr(&m.logs_emitted_total.value);
    const dropped_addr = @intFromPtr(&m.logs_dropped_total.value);
    const errors_addr = @intFromPtr(&m.handler_errors_total.value);

    // Each counter must start on a cache-line boundary relative to struct start.
    try std.testing.expect((emitted_addr - base) % cache_line == 0);
    try std.testing.expect((dropped_addr - base) % cache_line == 0);
    try std.testing.expect((errors_addr - base) % cache_line == 0);

    // Adjacent counters must be at least cache_line bytes apart.
    try std.testing.expect(dropped_addr - emitted_addr >= cache_line);
    try std.testing.expect(errors_addr - dropped_addr >= cache_line);
}
