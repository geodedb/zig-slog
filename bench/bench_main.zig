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

fn getIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

pub fn main() !void {
    const io = getIo();
    var stdout_buf: [8192]u8 = undefined;
    var stdout_fw = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_fw.interface;

    try stdout.print("\n", .{});
    try stdout.print("==============================================================\n", .{});
    try stdout.print("                    slogz Benchmark Suite                      \n", .{});
    try stdout.print("==============================================================\n", .{});
    try stdout.print("  Iterations: {d:>10}                                      \n", .{BENCHMARK_ITERATIONS});
    try stdout.print("==============================================================\n", .{});
    try stdout.print("\n", .{});

    // Run benchmarks
    try benchDiscardHandler(stdout);
    try benchTextHandler(stdout);
    try benchJsonHandler(stdout);
    try benchLoggerDisabled(stdout);
    try benchLoggerEnabled(stdout);
    try benchTimestampFormatting(stdout);
    try benchAttrCreation(stdout);
    try benchQueuedRecord(stdout);
    try benchIsSensitiveKey(stdout);
    try benchAsyncHandler(stdout);

    try stdout.print("\n", .{});
    try stdout.print("Benchmark complete.\n", .{});
    try stdout.flush();
}

fn elapsed_ns(start: std.Io.Timestamp, end: std.Io.Timestamp) u64 {
    const dur = start.durationTo(end);
    return @intCast(@max(dur.nanoseconds, 0));
}

fn benchDiscardHandler(stdout: *std.Io.Writer) !void {
    const io = getIo();
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
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        try handler.handle(&rec);
    }
    const end = std.Io.Timestamp.now(io, .awake);

    printResult(stdout, "DiscardHandler.handle", elapsed_ns(start, end));
}

fn benchTextHandler(stdout: *std.Io.Writer) !void {
    const io = getIo();
    var buf: [8192]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.text.Context.init(&fbs, .info, Clock.system());
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
        fbs.end = 0;
        try handler.handle(&rec);
    }

    // Benchmark
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        fbs.end = 0;
        try handler.handle(&rec);
    }
    const end = std.Io.Timestamp.now(io, .awake);

    printResult(stdout, "TextHandler.handle", elapsed_ns(start, end));
}

fn benchJsonHandler(stdout: *std.Io.Writer) !void {
    const io = getIo();
    var buf: [8192]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.json.Context.init(&fbs, .info, Clock.system());
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
        fbs.end = 0;
        try handler.handle(&rec);
    }

    // Benchmark
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        fbs.end = 0;
        try handler.handle(&rec);
    }
    const end = std.Io.Timestamp.now(io, .awake);

    printResult(stdout, "JsonHandler.handle", elapsed_ns(start, end));
}

fn benchLoggerDisabled(stdout: *std.Io.Writer) !void {
    const io = getIo();
    const handler = slogz.discardHandler();
    const logger = Logger.init(handler, .@"error", Clock.system());

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        logger.info("bench.test", &.{
            Attr.string("key", "value"),
        }) catch {};
    }

    // Benchmark (logging at info when level is error - should be fast)
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        logger.info("bench.test", &.{
            Attr.string("key", "value"),
        }) catch {};
    }
    const end = std.Io.Timestamp.now(io, .awake);

    printResult(stdout, "Logger.info (disabled)", elapsed_ns(start, end));
}

fn benchLoggerEnabled(stdout: *std.Io.Writer) !void {
    const io = getIo();
    const handler = slogz.discardHandler();
    const logger = Logger.init(handler, .info, Clock.system());

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        logger.info("bench.test", &.{
            Attr.string("key", "value"),
        }) catch {};
    }

    // Benchmark
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        logger.info("bench.test", &.{
            Attr.string("key", "value"),
        }) catch {};
    }
    const end = std.Io.Timestamp.now(io, .awake);

    printResult(stdout, "Logger.info (enabled)", elapsed_ns(start, end));
}

fn benchTimestampFormatting(stdout: *std.Io.Writer) !void {
    const io = getIo();
    var buf: [27]u8 = undefined;
    const timestamp: i128 = 1735787045000000;

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        slogz.rfc3339.formatTimestamp(&buf, timestamp);
    }

    // Benchmark
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        slogz.rfc3339.formatTimestamp(&buf, timestamp);
    }
    const end = std.Io.Timestamp.now(io, .awake);

    printResult(stdout, "RFC3339.format", elapsed_ns(start, end));
}

fn benchAttrCreation(stdout: *std.Io.Writer) !void {
    const io = getIo();
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
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        const a1 = Attr.string("key", "value");
        const a2 = Attr.int("count", 42);
        const a3 = Attr.float("ratio", 0.5);
        const a4 = Attr.boolean("flag", true);
        sum += @intFromPtr(&a1) + @intFromPtr(&a2) + @intFromPtr(&a3) + @intFromPtr(&a4);
    }
    const end = std.Io.Timestamp.now(io, .awake);

    // Prevent optimization
    if (sum == 0) unreachable;

    printResult(stdout, "Attr creation (x4)", elapsed_ns(start, end));
}

fn benchQueuedRecord(stdout: *std.Io.Writer) !void {
    const io = getIo();
    const QueuedRecord = slogz.queue.QueuedRecord;

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "bench.test",
        .message = "Benchmark test message for serialization",
        .logger = "bench.service",
        .source_file = "main.zig",
        .source_line = 42,
        .attrs = &.{
            Attr.string("key1", "value1"),
            Attr.int("key2", 42),
            Attr.float("key3", 3.14159),
            Attr.boolean("key4", true),
        },
    };

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        const qr = QueuedRecord.fromRecord(&rec);
        std.mem.doNotOptimizeAway(&qr);
    }

    // Benchmark
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        const qr = QueuedRecord.fromRecord(&rec);
        std.mem.doNotOptimizeAway(&qr);
    }
    const end = std.Io.Timestamp.now(io, .awake);

    printResult(stdout, "QueuedRecord.fromRecord", elapsed_ns(start, end));
}

fn benchIsSensitiveKey(stdout: *std.Io.Writer) !void {
    const io = getIo();
    const isSensitiveKey = slogz.redact.isSensitiveKey;

    // Test keys of varying sensitivity
    const keys = [_][]const u8{
        "password", // sensitive, short
        "username", // not sensitive
        "api_key_v2", // sensitive, medium
        "request_method", // not sensitive, medium
        "connection_string_primary", // sensitive, long
        "x", // not sensitive, minimal
    };

    // Warmup
    var warm_sum: usize = 0;
    for (0..WARMUP_ITERATIONS) |_| {
        for (keys) |key| {
            warm_sum += @intFromBool(isSensitiveKey(key));
        }
    }
    std.mem.doNotOptimizeAway(&warm_sum);

    // Benchmark
    var sum: usize = 0;
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        for (keys) |key| {
            sum += @intFromBool(isSensitiveKey(key));
        }
    }
    const end = std.Io.Timestamp.now(io, .awake);

    // Prevent optimization
    if (sum == 0) unreachable;

    printResult(stdout, "isSensitiveKey (x6 keys)", elapsed_ns(start, end));
}

fn benchAsyncHandler(stdout: *std.Io.Writer) !void {
    const io = getIo();
    // Measure async handler enqueue throughput using a discard inner handler.
    // We create the async context, start it, enqueue records, then stop it.
    const allocator = std.heap.page_allocator;

    const discard_handler = slogz.discardHandler();
    var ctx = slogz.async_handler.Context.init(allocator, .{
        .inner = discard_handler,
        .queue_size = 8192,
        .drop_oldest = true,
    }) catch {
        stdout.print("  {s:<30} SKIPPED (init failed)\n", .{"AsyncHandler.enqueue"}) catch {};
        return;
    };
    ctx.start() catch {
        ctx.deinit();
        stdout.print("  {s:<30} SKIPPED (start failed)\n", .{"AsyncHandler.enqueue"}) catch {};
        return;
    };
    const handler = slogz.async_handler.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "bench.async",
        .message = "Async benchmark message",
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
        handler.handle(&rec) catch {};
    }

    // Benchmark
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..BENCHMARK_ITERATIONS) |_| {
        handler.handle(&rec) catch {};
    }
    const end = std.Io.Timestamp.now(io, .awake);

    // Shutdown gracefully
    ctx.deinit();

    printResult(stdout, "AsyncHandler.enqueue", elapsed_ns(start, end));
}

fn printResult(stdout: *std.Io.Writer, name: []const u8, total_ns: u64) void {
    const ns_per_op = total_ns / BENCHMARK_ITERATIONS;
    const ops_per_sec = if (ns_per_op > 0) 1_000_000_000 / ns_per_op else 0;

    stdout.print("  {s:<30} {d:>8} ns/op  ({d:>10} ops/sec)\n", .{
        name,
        ns_per_op,
        ops_per_sec,
    }) catch {};
}
