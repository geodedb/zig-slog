// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Secret redaction example.
//!
//! Demonstrates how sensitive values are automatically redacted
//! when using Attr.secret(). This prevents credentials, API keys,
//! and other sensitive data from appearing in logs.

const std = @import("std");
const slog = @import("slogz");

pub fn main() !void {
    // Create handlers for both text (stderr) and JSON (stdout) output
    var text_ctx: slog.text.Context = undefined;
    const text_handler = slog.stderrHandler(&text_ctx, .info);
    // The stderr writer is buffered; flush so short runs emit everything.
    defer text_ctx.writer.flush() catch {};

    var out_buf: [4096]u8 = undefined;
    var out_writer = std.Io.File.stdout().writer(
        std.Io.Threaded.global_single_threaded.io(),
        &out_buf,
    );
    defer out_writer.interface.flush() catch {};
    var json_ctx = slog.json.Context.init(
        &out_writer.interface,
        .info,
        slog.Clock.system(),
    );
    const json_handler = slog.json.init(&json_ctx);

    // Create loggers
    const text_logger = slog.Logger.init(text_handler, .info, slog.Clock.system())
        .named("security-demo");
    const json_logger = slog.Logger.init(json_handler, .info, slog.Clock.system())
        .named("security-demo");

    std.debug.print("=== Secret Redaction Example ===\n\n", .{});
    std.debug.print("Text output (stderr):\n", .{});

    // Database connection - password is redacted
    try text_logger.info("Database connected", &.{
        slog.Attr.string("host", "db.example.com"),
        slog.Attr.int("port", 5432),
        slog.Attr.string("database", "production"),
        slog.Attr.string("user", "app_user"),
        slog.Attr.secret("password", "super_secret_password_123!"),
    });

    // API authentication - tokens are redacted
    try text_logger.info("External API authenticated", &.{
        slog.Attr.string("service", "payment-gateway"),
        slog.Attr.secret("api_key", "sk_live_abc123xyz789secret"),
        slog.Attr.secret("api_secret", "whsec_extremely_sensitive_data"),
        slog.Attr.int("status", 200),
    });

    // User authentication - sensitive session data is redacted
    try text_logger.info("User authenticated", &.{
        slog.Attr.string("username", "alice"),
        slog.Attr.string("email", "alice@example.com"),
        slog.Attr.secret("session_token", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."),
        slog.Attr.secret("refresh_token", "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4..."),
    });

    std.debug.print("\n--- JSON output (stdout): ---\n", .{});

    // Same logs in JSON format - secrets still redacted
    try json_logger.info("Database connected", &.{
        slog.Attr.string("host", "db.example.com"),
        slog.Attr.string("user", "app_user"),
        slog.Attr.secret("password", "super_secret_password_123!"),
    });

    try json_logger.info("API call with credentials", &.{
        slog.Attr.string("endpoint", "https://api.stripe.com/v1/charges"),
        slog.Attr.secret("bearer_token", "sk_test_4eC39HqLyjWDarjtT1zdp7dc"),
        slog.Attr.int("response_code", 200),
    });

    std.debug.print("\n--- Summary ---\n", .{});
    std.debug.print("Notice that all secret values show as [REDACTED]\n", .{});
    std.debug.print("The actual secret values never appear in log output.\n", .{});
}
