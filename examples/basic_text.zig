// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Basic text logging example.
//!
//! Demonstrates the simplest usage of slog with the text handler,
//! writing human-readable log output to stderr.

const std = @import("std");
const slog = @import("slog");

pub fn main() !void {
    // Create a text handler writing to stderr
    var ctx = slog.text.Context.init(
        std.io.getStdErr().writer().any(),
        .info,
        slog.Clock.system(),
    );
    const handler = slog.text.init(&ctx);

    // Create a logger with a name
    const logger = slog.Logger.init(handler, .info, slog.Clock.system())
        .named("myapp");

    // Log at various levels
    try logger.info("Application started", &.{
        slog.Attr.string("version", "1.0.0"),
        slog.Attr.int("port", 8080),
    });

    try logger.debug("This won't appear (below info level)", &.{});

    try logger.warn("Configuration file not found, using defaults", &.{
        slog.Attr.string("config_path", "/etc/myapp/config.toml"),
    });

    // Log with various attribute types
    try logger.info("Request processed", &.{
        slog.Attr.string("method", "GET"),
        slog.Attr.string("path", "/api/users"),
        slog.Attr.int("status", 200),
        slog.Attr.float("duration_ms", 12.5),
        slog.Attr.boolean("cached", true),
    });

    // Log errors
    try logger.@"error"("Database connection failed", &.{
        slog.Attr.err("error", error.ConnectionRefused),
        slog.Attr.string("host", "localhost"),
        slog.Attr.int("port", 5432),
    });

    std.debug.print("\n--- Text handler output complete ---\n", .{});
}
