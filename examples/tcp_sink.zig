// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! TCP sink example.
//!
//! Demonstrates sending logs over TCP to a remote log collector.
//! Includes automatic reconnection and retry with exponential backoff.
//!
//! To test, run a TCP listener first:
//!   nc -l 5514
//! Or use a log aggregation system like Logstash, Fluentd, or Vector.

const std = @import("std");
const slog = @import("slog");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("TCP Sink Example\n", .{});
    std.debug.print("================\n\n", .{});
    std.debug.print("This example sends logs to localhost:5514\n", .{});
    std.debug.print("Start a listener first: nc -l 5514\n\n", .{});

    // Configure TCP sink with retry settings
    var tcp_ctx = slog.tcp_sink.Context.init(allocator, .{
        .host = "127.0.0.1",
        .port = 5514,
        .connect_timeout_ms = 5000,
        .max_retries = 3,
        .initial_backoff_ms = 100,
        .max_backoff_ms = 5000,
    }, .info, slog.Clock.system());
    defer tcp_ctx.deinit();

    const handler = slog.tcp_sink.init(&tcp_ctx);
    const logger = slog.Logger.init(handler, .info, slog.Clock.system())
        .named("tcp-example");

    // Attempt to send logs (will retry on connection failure)
    std.debug.print("Attempting to send logs...\n", .{});

    logger.info("Connection established", &.{
        slog.Attr.string("protocol", "tcp"),
        slog.Attr.string("host", "127.0.0.1"),
        slog.Attr.int("port", 5514),
    }) catch |err| {
        std.debug.print("Failed to send log: {any}\n", .{err});
        std.debug.print("Make sure a TCP listener is running on port 5514\n", .{});
        return;
    };

    // Send some application logs
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        logger.info("Event processed", &.{
            slog.Attr.uint("event_id", i),
            slog.Attr.string("source", "sensor-01"),
            slog.Attr.float("value", @as(f64, @floatFromInt(i)) * 1.5),
        }) catch |err| {
            std.debug.print("Send failed: {any}\n", .{err});
            break;
        };
    }

    std.debug.print("Sent {d} log records\n", .{i});

    // Check metrics
    const m = slog.getMetrics();
    std.debug.print("Total bytes written: {d}\n", .{m.bytes_written});
    std.debug.print("Total records emitted: {d}\n", .{m.records_emitted});
}
