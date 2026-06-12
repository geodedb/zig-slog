// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! JSON logging example.
//!
//! Demonstrates structured JSON output suitable for log aggregation
//! systems like Elasticsearch, Splunk, or Loki.

const std = @import("std");
const slog = @import("slogz");

pub fn main() !void {
    // Create a JSON handler writing to stdout (for piping to log systems)
    var out_buf: [4096]u8 = undefined;
    var out_writer = std.Io.File.stdout().writer(
        std.Io.Threaded.global_single_threaded.io(),
        &out_buf,
    );
    defer out_writer.interface.flush() catch {};
    var ctx = slog.json.Context.init(
        &out_writer.interface,
        .debug, // Lower threshold to see all messages
        slog.Clock.system(),
    );
    const handler = slog.json.init(&ctx);

    // Create a named logger
    const logger = slog.Logger.init(handler, .debug, slog.Clock.system())
        .named("api-server");

    // Basic info log - outputs single JSON line
    try logger.info("Server starting", &.{
        slog.Attr.string("environment", "production"),
        slog.Attr.int("workers", 4),
    });

    // Request logging with structured data
    try logger.info("HTTP request", &.{
        slog.Attr.string("method", "POST"),
        slog.Attr.string("path", "/api/v1/users"),
        slog.Attr.string("client_ip", "192.168.1.100"),
        slog.Attr.int("status", 201),
        slog.Attr.float("latency_ms", 45.2),
        slog.Attr.uint("request_size", 1024),
        slog.Attr.uint("response_size", 256),
    });

    // Debug logging with detailed context
    try logger.debug("Cache lookup", &.{
        slog.Attr.string("cache_key", "user:12345"),
        slog.Attr.boolean("hit", false),
        slog.Attr.int("ttl_seconds", 3600),
    });

    // Error logging with error type
    try logger.@"error"("Database query failed", &.{
        slog.Attr.err("error", error.Timeout),
        slog.Attr.string("query", "SELECT * FROM users WHERE id = $1"),
        slog.Attr.float("timeout_ms", 5000.0),
        slog.Attr.int("retry_count", 3),
    });

    // Demonstrate secret redaction - API keys never appear in logs
    try logger.info("External API call", &.{
        slog.Attr.string("service", "payment-gateway"),
        slog.Attr.secret("api_key", "sk_live_abc123xyz789"),
        slog.Attr.int("status", 200),
    });

    std.debug.print("\n--- JSON output complete (check stdout) ---\n", .{});
}
