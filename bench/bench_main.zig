//! slogz Benchmark Suite
//!
//! Measures performance of various logging operations.
//! Run with: zig build bench

const std = @import("std");
const slogz = @import("slogz");

const Attr = slogz.Attr;
const Record = slogz.Record;
const Level = slogz.Level;
const Clock = slogz.Clock;
const Logger = slogz.Logger;

// Benchmark configuration
const WARMUP_ITERATIONS = 1000;
const BENCHMARK_ITERATIONS = 100_000;

pub fn main() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();

    try stdout.print("\n", .{});
    try stdout.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    try stdout.print("║                    slogz Benchmark Suite                     ║\n", .{});
    try stdout.print("╠══════════════════════════════════════════════════════════════╣\n", .{});
    try stdout.print("║  Iterations: {d:>10}                                      ║\n", .{BENCHMARK_ITERATIONS});
    try stdout.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    try stdout.print("\n", .{});

    // Run benchmarks
    try benchDiscardHandler(stdout);
    try benchTextHandler(stdout);
    try benchJsonHandler(stdout);
    try benchLoggerDisabled(stdout);
    try benchLoggerEnabled(stdout);
    try benchTimestampFormatting(stdout);
    try benchAttrCreation(stdout);

    try stdout.print("\n", .{});
    try stdout.print("Benchmark complete.\n", .{});
}

fn benchDiscardHandler(stdout: anytype) !void {
    const handler = slogz.discardHandler();

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "bench.test",
        .message = "Benchmark test message",
        .logger = "bench",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("key1", "value1"),
            Attr.int("key2", 42),
        },
    };

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        try handler.handle(&rec);
    }

    // Benchmark
    var timer = try std.time.Timer.start();
    for (0..BENCHMARK_ITERATIONS) |_| {
        try handler.handle(&rec);
    }
    const elapsed_ns = timer.read();

    printResult(stdout, "DiscardHandler.handle", elapsed_ns);
}

fn benchTextHandler(stdout: anytype) !void {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.text.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.text.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "bench.test",
        .message = "Benchmark test message",
        .logger = "bench",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("key1", "value1"),
            Attr.int("key2", 42),
        },
    };

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        fbs.reset();
        try handler.handle(&rec);
    }

    // Benchmark
    var timer = try std.time.Timer.start();
    for (0..BENCHMARK_ITERATIONS) |_| {
        fbs.reset();
        try handler.handle(&rec);
    }
    const elapsed_ns = timer.read();

    printResult(stdout, "TextHandler.handle", elapsed_ns);
}

fn benchJsonHandler(stdout: anytype) !void {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.json.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "bench.test",
        .message = "Benchmark test message",
        .logger = "bench",
        .source_file = "main.zig",
        .source_line = 42,
        .attrs = &.{
            Attr.string("key1", "value1"),
            Attr.int("key2", 42),
            Attr.float("key3", 3.14159),
        },
    };

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        fbs.reset();
        try handler.handle(&rec);
    }

    // Benchmark
    var timer = try std.time.Timer.start();
    for (0..BENCHMARK_ITERATIONS) |_| {
        fbs.reset();
        try handler.handle(&rec);
    }
    const elapsed_ns = timer.read();

    printResult(stdout, "JsonHandler.handle", elapsed_ns);
}

fn benchLoggerDisabled(stdout: anytype) !void {
    const handler = slogz.discardHandler();
    const logger = Logger.init(handler, .@"error", Clock.system());

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        logger.info("bench.test", &.{
            Attr.string("key", "value"),
        }) catch {};
    }

    // Benchmark (logging at info when level is error - should be fast)
    var timer = try std.time.Timer.start();
    for (0..BENCHMARK_ITERATIONS) |_| {
        logger.info("bench.test", &.{
            Attr.string("key", "value"),
        }) catch {};
    }
    const elapsed_ns = timer.read();

    printResult(stdout, "Logger.info (disabled)", elapsed_ns);
}

fn benchLoggerEnabled(stdout: anytype) !void {
    const handler = slogz.discardHandler();
    const logger = Logger.init(handler, .info, Clock.system());

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        logger.info("bench.test", &.{
            Attr.string("key", "value"),
        }) catch {};
    }

    // Benchmark
    var timer = try std.time.Timer.start();
    for (0..BENCHMARK_ITERATIONS) |_| {
        logger.info("bench.test", &.{
            Attr.string("key", "value"),
        }) catch {};
    }
    const elapsed_ns = timer.read();

    printResult(stdout, "Logger.info (enabled)", elapsed_ns);
}

fn benchTimestampFormatting(stdout: anytype) !void {
    var buf: [27]u8 = undefined;
    const timestamp: i128 = 1735787045000000;

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        slogz.rfc3339.formatTimestamp(&buf, timestamp);
    }

    // Benchmark
    var timer = try std.time.Timer.start();
    for (0..BENCHMARK_ITERATIONS) |_| {
        slogz.rfc3339.formatTimestamp(&buf, timestamp);
    }
    const elapsed_ns = timer.read();

    printResult(stdout, "RFC3339.format", elapsed_ns);
}

fn benchAttrCreation(stdout: anytype) !void {
    var sum: usize = 0;

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        const a1 = Attr.string("key", "value");
        const a2 = Attr.int("count", 42);
        const a3 = Attr.float("ratio", 0.5);
        const a4 = Attr.boolean("flag", true);
        sum += @intFromPtr(&a1) + @intFromPtr(&a2) + @intFromPtr(&a3) + @intFromPtr(&a4);
    }

    // Benchmark
    var timer = try std.time.Timer.start();
    for (0..BENCHMARK_ITERATIONS) |_| {
        const a1 = Attr.string("key", "value");
        const a2 = Attr.int("count", 42);
        const a3 = Attr.float("ratio", 0.5);
        const a4 = Attr.boolean("flag", true);
        sum += @intFromPtr(&a1) + @intFromPtr(&a2) + @intFromPtr(&a3) + @intFromPtr(&a4);
    }
    const elapsed_ns = timer.read();

    // Prevent optimization
    if (sum == 0) unreachable;

    printResult(stdout, "Attr creation (x4)", elapsed_ns);
}

fn printResult(stdout: anytype, name: []const u8, elapsed_ns: u64) void {
    const ns_per_op = elapsed_ns / BENCHMARK_ITERATIONS;
    const ops_per_sec = if (ns_per_op > 0) 1_000_000_000 / ns_per_op else 0;

    stdout.print("  {s:<30} {d:>8} ns/op  ({d:>10} ops/sec)\n", .{
        name,
        ns_per_op,
        ops_per_sec,
    }) catch {};
}
