// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Metrics export example.
//!
//! Demonstrates exporting logging metrics in Prometheus format.
//! Useful for monitoring logging throughput, errors, and queue status.

const std = @import("std");
const slog = @import("slogz");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Reset metrics for clean demo
    slog.metrics.reset();

    // Create a text handler writing to stderr
    var text_ctx: slog.text.Context = undefined;
    const text_handler = slog.stderrHandler(&text_ctx, .info);
    // The stderr writer is buffered; flush so short runs emit everything.
    defer text_ctx.writer.flush() catch {};

    // Async handler to demonstrate queue metrics
    var async_ctx = try slog.async_handler.Context.init(allocator, .{
        .inner = text_handler,
        .queue_size = 100,
        .drop_oldest = true,
    });
    defer async_ctx.deinit();
    try async_ctx.start(); // spawn the worker thread (two-step init)

    const handler = slog.async_handler.init(&async_ctx);
    const logger = slog.Logger.init(handler, .info, slog.Clock.system())
        .named("metrics-demo");

    std.debug.print("=== Metrics Export Example ===\n\n", .{});
    std.debug.print("Generating log traffic...\n\n", .{});

    // Generate some log traffic
    var i: u32 = 0;
    while (i < 25) : (i += 1) {
        try logger.info("Processing request", &.{
            slog.Attr.uint("request_id", i),
            slog.Attr.string("method", "GET"),
        });
    }

    // Flush to process all queued records
    try handler.flush(5000);

    std.debug.print("\n--- Simple Metrics API ---\n", .{});
    const simple_metrics = slog.getMetrics();
    std.debug.print("Bytes written: {d}\n", .{simple_metrics.bytes_written});
    std.debug.print("Records emitted: {d}\n", .{simple_metrics.records_emitted});

    std.debug.print("\n--- Full Metrics Snapshot ---\n", .{});
    const snap = slog.metrics.global.snapshot();
    std.debug.print("logs_emitted_total: {d}\n", .{snap.logs_emitted_total});
    std.debug.print("logs_dropped_total: {d}\n", .{snap.logs_dropped_total});
    std.debug.print("handler_errors_total: {d}\n", .{snap.handler_errors_total});
    std.debug.print("bytes_written_total: {d}\n", .{snap.bytes_written_total});
    std.debug.print("queue_size: {d}\n", .{snap.queue_size});
    std.debug.print("rotations_total: {d}\n", .{snap.rotations_total});
    std.debug.print("reconnections_total: {d}\n", .{snap.reconnections_total});

    std.debug.print("\n--- Prometheus Format ---\n", .{});
    var buf: [4096]u8 = undefined;
    const prometheus_output = slog.exportPrometheusMetrics(&buf);
    std.debug.print("{s}\n", .{prometheus_output});

    std.debug.print("--- Usage Notes ---\n", .{});
    std.debug.print("Expose the Prometheus output via HTTP for scraping:\n", .{});
    std.debug.print("  GET /metrics -> slog.exportPrometheusMetrics(buf)\n", .{});
}
