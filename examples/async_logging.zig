// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Async handler example.
//!
//! Demonstrates non-blocking logging using a background thread.
//! Log calls return immediately while a worker thread handles
//! delivery to the underlying handler.

const std = @import("std");
const slog = @import("slogz");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create the underlying text handler writing to stderr
    var text_ctx: slog.text.Context = undefined;
    const text_handler = slog.stderrHandler(&text_ctx, .info);
    // The stderr writer is buffered; flush so short runs emit everything.
    defer text_ctx.writer.flush() catch {};

    // Wrap it with async handler for non-blocking logging
    var async_ctx = try slog.async_handler.Context.init(allocator, .{
        .inner = text_handler,
        .queue_size = 1024, // Buffer up to 1024 records
        .drop_oldest = true, // Drop oldest when queue is full
        .block_timeout_ms = 0, // Non-blocking mode
    });
    defer async_ctx.deinit();

    const handler = slog.async_handler.init(&async_ctx);
    const logger = slog.Logger.init(handler, .info, slog.Clock.system())
        .named("async-example");

    std.debug.print("Starting async logging example...\n\n", .{});

    // These calls return immediately - logging happens in background
    try logger.info("Starting high-throughput operation", &.{
        slog.Attr.string("mode", "async"),
    });

    // Simulate rapid logging (non-blocking)
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        try logger.info("Processing item", &.{
            slog.Attr.uint("item_id", i),
            slog.Attr.boolean("async", true),
        });
    }

    try logger.info("Submitted all items to queue", &.{
        slog.Attr.uint("total", 50),
    });

    // Check metrics
    const dropped = slog.async_handler.getDroppedCount(handler);
    std.debug.print("\nDropped records: {d}\n", .{dropped});

    // Flush to ensure all queued records are delivered
    std.debug.print("Flushing async queue...\n\n", .{});
    try handler.flush(5000);

    // Export metrics
    var metrics_buf: [2048]u8 = undefined;
    const metrics_output = slog.exportPrometheusMetrics(&metrics_buf);
    std.debug.print("\n--- Prometheus Metrics ---\n{s}\n", .{metrics_output});
}
