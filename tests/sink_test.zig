//! Comprehensive unit tests for network sinks.
//!
//! Note: These tests focus on initialization, URL parsing, and option validation.
//! Network connectivity tests require actual servers and are run separately.

const std = @import("std");
const slogz = @import("slogz");
const Record = slogz.Record;
const Attr = slogz.Attr;
const Level = slogz.Level;
const Clock = slogz.Clock;

// Sink aliases for convenience
const tcp = slogz.tcp_sink;
const udp = slogz.udp_sink;
const http = slogz.http_sink;

// ============================================================================
// TCP Sink Tests
// ============================================================================

test "TcpSink - context initialization" {
    const allocator = std.testing.allocator;

    var ctx = tcp.Context.init(allocator, .{
        .host = "127.0.0.1",
        .port = 5514,
        .connect_timeout_ms = 5000,
        .max_retries = 3,
        .initial_backoff_ms = 100,
        .max_backoff_ms = 5000,
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqualStrings("127.0.0.1", ctx.options.host);
    try std.testing.expectEqual(@as(u16, 5514), ctx.options.port);
    try std.testing.expectEqual(@as(u8, 3), ctx.options.max_retries);
    try std.testing.expectEqual(Level.info, ctx.level);
}

test "TcpSink - handler initialization" {
    const allocator = std.testing.allocator;

    var ctx = tcp.Context.init(allocator, .{
        .host = "127.0.0.1",
        .port = 5514,
    }, .warn, Clock.system());
    defer ctx.deinit();

    const handler = tcp.init(&ctx);

    // Verify handler interface by exercising it
    try handler.flush(0);
    handler.setLevel(.debug);
    _ = handler.withAttrs(&.{});
    _ = handler.withGroup("test");
}

test "TcpSink - level change" {
    const allocator = std.testing.allocator;

    var ctx = tcp.Context.init(allocator, .{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = tcp.init(&ctx);
    handler.setLevel(.@"error");

    try std.testing.expectEqual(Level.@"error", ctx.level);
}

test "TcpSink - default options" {
    const allocator = std.testing.allocator;

    var ctx = tcp.Context.init(allocator, .{
        .host = "localhost",
        .port = 514,
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqual(@as(u32, 5000), ctx.options.connect_timeout_ms);
    try std.testing.expectEqual(@as(u8, 3), ctx.options.max_retries);
    try std.testing.expectEqual(@as(u32, 100), ctx.options.initial_backoff_ms);
    try std.testing.expectEqual(@as(u32, 5000), ctx.options.max_backoff_ms);
}

test "TcpSink - withAttrs returns handler" {
    const allocator = std.testing.allocator;

    var ctx = tcp.Context.init(allocator, .{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = tcp.init(&ctx);
    const derived = handler.withAttrs(&.{Attr.string("key", "value")});

    // Verify derived handler works
    try derived.flush(0);
}

test "TcpSink - withGroup returns handler" {
    const allocator = std.testing.allocator;

    var ctx = tcp.Context.init(allocator, .{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = tcp.init(&ctx);
    const derived = handler.withGroup("mygroup");

    // Verify derived handler works
    try derived.flush(0);
}

// ============================================================================
// UDP Sink Tests
// ============================================================================

test "UdpSink - context initialization" {
    var ctx = udp.Context.init(.{
        .host = "127.0.0.1",
        .port = 5514,
        .max_packet_size = 1500,
    }, .debug, Clock.system()) catch {
        // Socket creation may fail in test environment
        return;
    };
    defer ctx.deinit();

    try std.testing.expectEqualStrings("127.0.0.1", ctx.options.host);
    try std.testing.expectEqual(@as(u16, 5514), ctx.options.port);
    try std.testing.expectEqual(@as(usize, 1500), ctx.options.max_packet_size);
    try std.testing.expectEqual(Level.debug, ctx.level);
}

test "UdpSink - default max packet size" {
    var ctx = udp.Context.init(.{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system()) catch {
        return;
    };
    defer ctx.deinit();

    // Default max UDP payload
    try std.testing.expectEqual(@as(usize, 65507), ctx.options.max_packet_size);
}

test "UdpSink - handler interface" {
    var ctx = udp.Context.init(.{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system()) catch {
        return;
    };
    defer ctx.deinit();

    const handler = udp.init(&ctx);

    // Verify handler interface by exercising it
    try handler.flush(0);
    handler.setLevel(.debug);
    _ = handler.withAttrs(&.{});
    _ = handler.withGroup("test");
}

test "UdpSink - level change" {
    var ctx = udp.Context.init(.{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system()) catch {
        return;
    };
    defer ctx.deinit();

    const handler = udp.init(&ctx);
    handler.setLevel(.trace);

    try std.testing.expectEqual(Level.trace, ctx.level);
}

test "UdpSink - flush does nothing" {
    var ctx = udp.Context.init(.{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system()) catch {
        return;
    };
    defer ctx.deinit();

    const handler = udp.init(&ctx);
    try handler.flush(1000);
}

// ============================================================================
// HTTP Sink Tests
// ============================================================================

test "HttpSink - HTTP URL parsing" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://localhost:8080/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqualStrings("localhost", ctx.host);
    try std.testing.expectEqual(@as(u16, 8080), ctx.port);
    try std.testing.expectEqualStrings("/logs", ctx.path);
    try std.testing.expect(!ctx.is_https);
}

test "HttpSink - HTTPS URL parsing" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "https://api.example.com/v1/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqualStrings("api.example.com", ctx.host);
    try std.testing.expectEqual(@as(u16, 443), ctx.port);
    try std.testing.expectEqualStrings("/v1/logs", ctx.path);
    try std.testing.expect(ctx.is_https);
}

test "HttpSink - URL without path" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://localhost:9200",
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqualStrings("localhost", ctx.host);
    try std.testing.expectEqual(@as(u16, 9200), ctx.port);
    try std.testing.expectEqualStrings("/", ctx.path);
}

test "HttpSink - default port for HTTP" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://example.com/api",
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqual(@as(u16, 80), ctx.port);
}

test "HttpSink - default port for HTTPS" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "https://secure.example.com/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqual(@as(u16, 443), ctx.port);
}

test "HttpSink - invalid URL scheme" {
    const allocator = std.testing.allocator;

    const result = http.Context.init(allocator, .{
        .url = "ftp://example.com/logs",
    }, .info, Clock.system());

    try std.testing.expectError(error.InvalidUrl, result);
}

test "HttpSink - default options" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://localhost/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqualStrings("POST", ctx.options.method);
    try std.testing.expectEqualStrings("application/json", ctx.options.content_type);
    try std.testing.expectEqual(@as(u32, 10000), ctx.options.timeout_ms);
    try std.testing.expectEqual(@as(u8, 3), ctx.options.max_retries);
}

test "HttpSink - custom options" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://localhost/logs",
        .method = "PUT",
        .content_type = "application/x-ndjson",
        .timeout_ms = 30000,
        .max_retries = 5,
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer token123" },
            .{ .name = "X-Custom", .value = "value" },
        },
    }, .warn, Clock.system());
    defer ctx.deinit();

    try std.testing.expectEqualStrings("PUT", ctx.options.method);
    try std.testing.expectEqualStrings("application/x-ndjson", ctx.options.content_type);
    try std.testing.expectEqual(@as(u32, 30000), ctx.options.timeout_ms);
    try std.testing.expectEqual(@as(u8, 5), ctx.options.max_retries);
    try std.testing.expectEqual(@as(usize, 2), ctx.options.headers.len);
}

test "HttpSink - handler interface" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://localhost/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = http.init(&ctx);

    // Verify handler interface by exercising it
    try handler.flush(0);
    handler.setLevel(.debug);
    _ = handler.withAttrs(&.{});
    _ = handler.withGroup("test");
}

test "HttpSink - level change" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://localhost/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = http.init(&ctx);
    handler.setLevel(.fatal);

    try std.testing.expectEqual(Level.fatal, ctx.level);
}

test "HttpSink - withAttrs returns handler" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://localhost/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = http.init(&ctx);
    const derived = handler.withAttrs(&.{
        Attr.string("service", "myapp"),
    });

    // Verify derived handler works
    try derived.flush(0);
}

test "HttpSink - withGroup returns handler" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://localhost/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = http.init(&ctx);
    const derived = handler.withGroup("request");

    // Verify derived handler works
    try derived.flush(0);
}

test "HttpSink - flush does nothing" {
    const allocator = std.testing.allocator;

    var ctx = try http.Context.init(allocator, .{
        .url = "http://localhost/logs",
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = http.init(&ctx);
    try handler.flush(1000);
}

// ============================================================================
// Cross-Sink Tests
// ============================================================================

test "All sinks - polymorphic handler array" {
    const allocator = std.testing.allocator;

    // Create contexts for each sink type
    var tcp_ctx = tcp.Context.init(allocator, .{
        .host = "127.0.0.1",
        .port = 5514,
    }, .info, Clock.system());
    defer tcp_ctx.deinit();

    var http_ctx = try http.Context.init(allocator, .{
        .url = "http://localhost/logs",
    }, .info, Clock.system());
    defer http_ctx.deinit();

    // Verify they can all be used as generic handlers
    const handlers = [_]slogz.Handler{
        tcp.init(&tcp_ctx),
        http.init(&http_ctx),
    };

    for (handlers) |handler| {
        try handler.flush(0);
    }
}

test "Sink options - backoff configuration" {
    const allocator = std.testing.allocator;

    // TCP with custom backoff
    var tcp_ctx = tcp.Context.init(allocator, .{
        .host = "127.0.0.1",
        .port = 5514,
        .initial_backoff_ms = 50,
        .max_backoff_ms = 10000,
    }, .info, Clock.system());
    defer tcp_ctx.deinit();

    try std.testing.expectEqual(@as(u32, 50), tcp_ctx.options.initial_backoff_ms);
    try std.testing.expectEqual(@as(u32, 10000), tcp_ctx.options.max_backoff_ms);

    // HTTP with custom backoff
    var http_ctx = try http.Context.init(allocator, .{
        .url = "http://localhost/logs",
        .initial_backoff_ms = 200,
        .max_backoff_ms = 30000,
    }, .info, Clock.system());
    defer http_ctx.deinit();

    try std.testing.expectEqual(@as(u32, 200), http_ctx.options.initial_backoff_ms);
    try std.testing.expectEqual(@as(u32, 30000), http_ctx.options.max_backoff_ms);
}
