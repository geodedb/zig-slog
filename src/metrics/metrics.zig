// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Metrics collection and export for slogz.
//!
//! Provides counters for logs emitted, dropped, and handler errors.
//! Supports Prometheus-style text export.

const std = @import("std");

/// Global metrics instance.
pub var global: Metrics = .{};

/// Reset global metrics (for testing).
pub fn reset() void {
    global = .{};
}

/// Metrics counters for logging operations.
pub const Metrics = struct {
    /// Total number of log records emitted.
    logs_emitted_total: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Total number of log records dropped (e.g., queue full).
    logs_dropped_total: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Total number of handler errors.
    handler_errors_total: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Total bytes written.
    bytes_written_total: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Records currently in async queue.
    queue_size: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Number of file rotations.
    rotations_total: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Number of network reconnections.
    reconnections_total: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// Increment logs emitted counter.
    pub fn incEmitted(self: *Metrics) void {
        _ = self.logs_emitted_total.fetchAdd(1, .monotonic);
    }

    /// Increment logs dropped counter.
    pub fn incDropped(self: *Metrics, count: u64) void {
        _ = self.logs_dropped_total.fetchAdd(count, .monotonic);
    }

    /// Increment handler errors counter.
    pub fn incErrors(self: *Metrics) void {
        _ = self.handler_errors_total.fetchAdd(1, .monotonic);
    }

    /// Add bytes written.
    pub fn addBytesWritten(self: *Metrics, bytes: u64) void {
        _ = self.bytes_written_total.fetchAdd(bytes, .monotonic);
    }

    /// Set queue size.
    pub fn setQueueSize(self: *Metrics, size: u64) void {
        self.queue_size.store(size, .monotonic);
    }

    /// Increment rotations counter.
    pub fn incRotations(self: *Metrics) void {
        _ = self.rotations_total.fetchAdd(1, .monotonic);
    }

    /// Increment reconnections counter.
    pub fn incReconnections(self: *Metrics) void {
        _ = self.reconnections_total.fetchAdd(1, .monotonic);
    }

    /// Get current values.
    pub fn snapshot(self: *const Metrics) MetricsSnapshot {
        return .{
            .logs_emitted_total = self.logs_emitted_total.load(.monotonic),
            .logs_dropped_total = self.logs_dropped_total.load(.monotonic),
            .handler_errors_total = self.handler_errors_total.load(.monotonic),
            .bytes_written_total = self.bytes_written_total.load(.monotonic),
            .queue_size = self.queue_size.load(.monotonic),
            .rotations_total = self.rotations_total.load(.monotonic),
            .reconnections_total = self.reconnections_total.load(.monotonic),
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
    logs_emitted_total: u64,
    logs_dropped_total: u64,
    handler_errors_total: u64,
    bytes_written_total: u64,
    queue_size: u64,
    rotations_total: u64,
    reconnections_total: u64,
};

test "Metrics basic operations" {
    var m = Metrics{};

    m.incEmitted();
    m.incEmitted();
    m.incDropped(3);
    m.incErrors();

    const snap = m.snapshot();
    try std.testing.expectEqual(@as(u64, 2), snap.logs_emitted_total);
    try std.testing.expectEqual(@as(u64, 3), snap.logs_dropped_total);
    try std.testing.expectEqual(@as(u64, 1), snap.handler_errors_total);
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
