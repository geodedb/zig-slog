// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Rotating file handler example.
//!
//! Demonstrates file-based logging with automatic rotation based on
//! file size. Useful for long-running services that need to manage
//! disk space.

const std = @import("std");
const slog = @import("slog");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Configure rotating file handler
    // - Rotates when file exceeds 1MB
    // - Keeps 5 backup files (app.log.1 through app.log.5)
    // - Deletes backups older than 7 days
    var ctx = try slog.rotating_file.Context.init(allocator, .{
        .path = "/tmp/slog-example/app.log",
        .max_bytes = 1 * 1024 * 1024, // 1MB
        .max_backups = 5,
        .max_age_days = 7,
        // Absolute paths bypass the cwd resolve-beneath sandbox
        // (SEC-0037) and require an explicit opt-in.
        .allow_absolute_path = true,
    }, .info, slog.Clock.system());
    defer ctx.deinit();

    const handler = slog.rotating_file.init(&ctx);
    const logger = slog.Logger.init(handler, .info, slog.Clock.system())
        .named("file-example");

    // Log some messages
    try logger.info("Application started", &.{
        slog.Attr.string("version", "2.1.0"),
        slog.Attr.int("pid", @intCast(std.os.linux.getpid())),
    });

    // Simulate some activity
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try logger.info("Processing batch", &.{
            slog.Attr.uint("batch_id", i),
            slog.Attr.uint("records_processed", i * 100 + 50),
            slog.Attr.float("duration_seconds", @as(f64, @floatFromInt(i)) * 0.1 + 0.5),
        });
    }

    try logger.info("Processing complete", &.{
        slog.Attr.uint("total_batches", 100),
    });

    // Flush to ensure all data is written
    try handler.flush(5000);

    std.debug.print("Log written to /tmp/slog-example/app.log\n", .{});
    std.debug.print("Check for rotated files: app.log.1, app.log.2, etc.\n", .{});
}
