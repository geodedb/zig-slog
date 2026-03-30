// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! slogz Incremental Scale Benchmark
//!
//! Runs benchmarks at increasing message volumes, producing structured
//! JSON output to stdout (human summary to stderr).
//!
//! Usage:
//!   zig build scale-bench                    # Run all tiers
//!   zig build scale-bench -- 10K             # Run single tier
//!   zig build scale-bench 2>/dev/null        # JSON only
//!   zig build scale-bench 2>/dev/null > results.json

const std = @import("std");
const builtin = @import("builtin");
const slogz = @import("slogz");

const Attr = slogz.Attr;
const Record = slogz.Record;
const Level = slogz.Level;
const Clock = slogz.Clock;
const Logger = slogz.Logger;

// ============================================================================
// Tier Configuration
// ============================================================================

const Tier = struct {
    name: []const u8,
    message_count: usize,
    attr_count: usize,
    warmup: usize,
    description: []const u8,
};

const tiers = [_]Tier{
    .{
        .name = "1K",
        .message_count = 1_000,
        .attr_count = 2,
        .warmup = 100,
        .description = "1K messages, 2 attrs",
    },
    .{
        .name = "10K",
        .message_count = 10_000,
        .attr_count = 2,
        .warmup = 1_000,
        .description = "10K messages, 2 attrs",
    },
    .{
        .name = "100K",
        .message_count = 100_000,
        .attr_count = 2,
        .warmup = 1_000,
        .description = "100K messages, 2 attrs",
    },
    .{
        .name = "100K-rich",
        .message_count = 100_000,
        .attr_count = 6,
        .warmup = 1_000,
        .description = "100K messages, 6 attrs (rich)",
    },
    .{
        .name = "500K",
        .message_count = 500_000,
        .attr_count = 2,
        .warmup = 1_000,
        .description = "500K messages, 2 attrs",
    },
    .{
        .name = "1M",
        .message_count = 1_000_000,
        .attr_count = 2,
        .warmup = 1_000,
        .description = "1M messages, 2 attrs",
    },
};

// ============================================================================
// Benchmark Results
// ============================================================================

const TierResult = struct {
    name: []const u8,
    message_count: usize,
    attr_count: usize,

    // Handler throughput (ops/sec)
    discard_ops_sec: u64,
    text_ops_sec: u64,
    json_ops_sec: u64,

    // Handler latency (ns/op)
    discard_ns_op: u64,
    text_ns_op: u64,
    json_ns_op: u64,

    // Logger overhead (ns/op)
    logger_disabled_ns: u64,
    logger_enabled_ns: u64,

    // Multi-handler (ns/op, 3 handlers)
    multi_handler_ns: u64,
    multi_handler_ops_sec: u64,

    // Async handler (ns/op enqueue)
    async_enqueue_ns: u64,
    async_enqueue_ops_sec: u64,

    // Formatting (ns/op)
    rfc3339_ns: u64,
    queued_record_ns: u64,
    sensitive_key_ns: u64,
};

// ============================================================================
// Benchmark Functions
// ============================================================================

const all_attrs = [_]Attr{
    Attr.string("service", "benchmark"),
    Attr.int("request_id", 12345),
    Attr.float("latency_ms", 1.234),
    Attr.boolean("cached", true),
    Attr.string("method", "GET"),
    Attr.string("path", "/api/v1/users"),
};

fn makeRecord(attr_count: usize) Record {
    return Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "bench.request",
        .message = "HTTP request completed successfully",
        .logger = "bench.http.server",
        .source_file = "server.zig",
        .source_line = 142,
        .attrs = all_attrs[0..@min(attr_count, all_attrs.len)],
    };
}

fn benchHandler(
    handler: slogz.Handler,
    rec: *const Record,
    warmup: usize,
    count: usize,
    comptime needs_reset: bool,
    fbs: anytype,
) struct { ns: u64, ops: u64 } {
    // Warmup
    for (0..warmup) |_| {
        if (needs_reset) fbs.reset();
        handler.handle(rec) catch {};
    }

    // Benchmark
    var timer = std.time.Timer.start() catch return .{ .ns = 0, .ops = 0 };
    for (0..count) |_| {
        if (needs_reset) fbs.reset();
        handler.handle(rec) catch {};
    }
    const elapsed_ns = timer.read();

    const ns_per_op = if (count > 0) elapsed_ns / count else 0;
    const ops_per_sec = if (ns_per_op > 0) 1_000_000_000 / ns_per_op else 0;

    return .{ .ns = ns_per_op, .ops = ops_per_sec };
}

const NoopFbs = struct {
    fn reset(_: *@This()) void {}
};

fn runTier(tier: Tier) TierResult {
    const rec = makeRecord(tier.attr_count);
    const count = tier.message_count;
    const warmup = tier.warmup;

    // --- Discard handler ---
    const discard_handler = slogz.discardHandler();
    var noop_fbs = NoopFbs{};
    const discard = benchHandler(discard_handler, &rec, warmup, count, false, &noop_fbs);

    // --- Text handler ---
    var text_buf: [16384]u8 = undefined;
    var text_fbs = std.io.fixedBufferStream(&text_buf);
    var text_ctx = slogz.text.Context.init(text_fbs.writer().any(), .info, Clock.system());
    const text_handler = slogz.text.init(&text_ctx);
    const text = benchHandler(text_handler, &rec, warmup, count, true, &text_fbs);

    // --- JSON handler ---
    var json_buf: [16384]u8 = undefined;
    var json_fbs = std.io.fixedBufferStream(&json_buf);
    var json_ctx = slogz.json.Context.init(json_fbs.writer().any(), .info, Clock.system());
    const json_handler = slogz.json.init(&json_ctx);
    const json_r = benchHandler(json_handler, &rec, warmup, count, true, &json_fbs);

    // --- Logger disabled ---
    const logger_disabled = blk: {
        const handler = slogz.discardHandler();
        const logger = Logger.init(handler, .@"error", Clock.system());

        for (0..warmup) |_| {
            logger.info("bench.test", &.{Attr.string("key", "value")}) catch {};
        }

        var timer = std.time.Timer.start() catch break :blk @as(u64, 0);
        for (0..count) |_| {
            logger.info("bench.test", &.{Attr.string("key", "value")}) catch {};
        }
        break :blk timer.read() / count;
    };

    // --- Logger enabled ---
    const logger_enabled = blk: {
        const handler = slogz.discardHandler();
        const logger = Logger.init(handler, .info, Clock.system());

        for (0..warmup) |_| {
            logger.info("bench.test", &.{Attr.string("key", "value")}) catch {};
        }

        var timer = std.time.Timer.start() catch break :blk @as(u64, 0);
        for (0..count) |_| {
            logger.info("bench.test", &.{Attr.string("key", "value")}) catch {};
        }
        break :blk timer.read() / count;
    };

    // --- Multi-handler (3 discard handlers) ---
    const multi = blk: {
        const children = [_]slogz.Handler{
            slogz.discardHandler(),
            slogz.discardHandler(),
            slogz.discardHandler(),
        };
        var multi_ctx = slogz.multi_handler.Context.init(&children, .info);
        const mh = slogz.multi_handler.init(&multi_ctx);

        for (0..warmup) |_| {
            mh.handle(&rec) catch {};
        }

        var timer = std.time.Timer.start() catch break :blk @as(u64, 0);
        for (0..count) |_| {
            mh.handle(&rec) catch {};
        }
        const elapsed = timer.read();
        const ns = elapsed / count;
        break :blk ns;
    };
    const multi_ops = if (multi > 0) 1_000_000_000 / multi else 0;

    // --- Async handler ---
    const async_result = blk: {
        const inner = slogz.discardHandler();
        var async_ctx = slogz.async_handler.Context.init(std.heap.page_allocator, .{
            .inner = inner,
            .queue_size = 8192,
            .drop_oldest = true,
        }) catch break :blk @as(u64, 0);
        async_ctx.start() catch {
            async_ctx.deinit();
            break :blk @as(u64, 0);
        };
        const ah = slogz.async_handler.init(&async_ctx);

        for (0..warmup) |_| {
            ah.handle(&rec) catch {};
        }

        var timer = std.time.Timer.start() catch {
            async_ctx.deinit();
            break :blk @as(u64, 0);
        };
        for (0..count) |_| {
            ah.handle(&rec) catch {};
        }
        const elapsed = timer.read();
        async_ctx.deinit();
        break :blk elapsed / count;
    };
    const async_ops = if (async_result > 0) 1_000_000_000 / async_result else 0;

    // --- RFC3339 formatting ---
    const rfc3339_ns = blk: {
        var ts_buf: [27]u8 = undefined;
        const timestamp: i128 = 1735787045000000;

        for (0..warmup) |_| {
            slogz.rfc3339.formatTimestamp(&ts_buf, timestamp);
        }

        var timer = std.time.Timer.start() catch break :blk @as(u64, 0);
        for (0..count) |_| {
            slogz.rfc3339.formatTimestamp(&ts_buf, timestamp);
        }
        break :blk timer.read() / count;
    };

    // --- QueuedRecord serialization ---
    const queued_ns = blk: {
        for (0..warmup) |_| {
            const qr = slogz.queue.QueuedRecord.fromRecord(&rec);
            std.mem.doNotOptimizeAway(&qr);
        }

        var timer = std.time.Timer.start() catch break :blk @as(u64, 0);
        for (0..count) |_| {
            const qr = slogz.queue.QueuedRecord.fromRecord(&rec);
            std.mem.doNotOptimizeAway(&qr);
        }
        break :blk timer.read() / count;
    };

    // --- Sensitive key check ---
    const sensitive_ns = blk: {
        const keys = [_][]const u8{
            "password",       "username",                  "api_key_v2",
            "request_method", "connection_string_primary", "x",
        };
        var warm_sum: usize = 0;
        for (0..warmup) |_| {
            for (keys) |key| warm_sum += @intFromBool(slogz.redact.isSensitiveKey(key));
        }
        std.mem.doNotOptimizeAway(&warm_sum);

        var sum: usize = 0;
        var timer = std.time.Timer.start() catch break :blk @as(u64, 0);
        for (0..count) |_| {
            for (keys) |key| sum += @intFromBool(slogz.redact.isSensitiveKey(key));
        }
        const elapsed = timer.read();
        std.mem.doNotOptimizeAway(&sum);
        break :blk elapsed / count;
    };

    return .{
        .name = tier.name,
        .message_count = tier.message_count,
        .attr_count = tier.attr_count,
        .discard_ops_sec = discard.ops,
        .text_ops_sec = text.ops,
        .json_ops_sec = json_r.ops,
        .discard_ns_op = discard.ns,
        .text_ns_op = text.ns,
        .json_ns_op = json_r.ns,
        .logger_disabled_ns = logger_disabled,
        .logger_enabled_ns = logger_enabled,
        .multi_handler_ns = multi,
        .multi_handler_ops_sec = multi_ops,
        .async_enqueue_ns = async_result,
        .async_enqueue_ops_sec = async_ops,
        .rfc3339_ns = rfc3339_ns,
        .queued_record_ns = queued_ns,
        .sensitive_key_ns = sensitive_ns,
    };
}

// ============================================================================
// JSON Output
// ============================================================================

fn writeJsonResults(results: []const TierResult) !void {
    const w = std.fs.File.stdout().deprecatedWriter();

    try w.print("{{\n", .{});
    try w.print("  \"version\": 1,\n", .{});

    // Timestamp
    const ts = std.time.timestamp();
    const epoch_secs: u64 = @intCast(ts);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day = es.getEpochDay();
    const yd = day.calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    try w.print("  \"timestamp\": \"{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z\",\n", .{
        yd.year,
        md.month.numeric(),
        md.day_index + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    });

    try w.print("  \"git_commit\": \"unknown\",\n", .{});
    try w.print("  \"system\": {{\n", .{});
    try w.print("    \"os\": \"{s}\",\n", .{@tagName(builtin.os.tag)});
    try w.print("    \"arch\": \"{s}\"\n", .{@tagName(builtin.cpu.arch)});
    try w.print("  }},\n", .{});
    try w.print("  \"tiers\": [\n", .{});

    for (results, 0..) |r, i| {
        try w.print("    {{\n", .{});
        try w.print("      \"name\": \"{s}\",\n", .{r.name});
        try w.print("      \"message_count\": {d},\n", .{r.message_count});
        try w.print("      \"attr_count\": {d},\n", .{r.attr_count});
        try w.print("      \"discard_ops_sec\": {d},\n", .{r.discard_ops_sec});
        try w.print("      \"text_ops_sec\": {d},\n", .{r.text_ops_sec});
        try w.print("      \"json_ops_sec\": {d},\n", .{r.json_ops_sec});
        try w.print("      \"discard_ns_op\": {d},\n", .{r.discard_ns_op});
        try w.print("      \"text_ns_op\": {d},\n", .{r.text_ns_op});
        try w.print("      \"json_ns_op\": {d},\n", .{r.json_ns_op});
        try w.print("      \"logger_disabled_ns\": {d},\n", .{r.logger_disabled_ns});
        try w.print("      \"logger_enabled_ns\": {d},\n", .{r.logger_enabled_ns});
        try w.print("      \"multi_handler_ns\": {d},\n", .{r.multi_handler_ns});
        try w.print("      \"multi_handler_ops_sec\": {d},\n", .{r.multi_handler_ops_sec});
        try w.print("      \"async_enqueue_ns\": {d},\n", .{r.async_enqueue_ns});
        try w.print("      \"async_enqueue_ops_sec\": {d},\n", .{r.async_enqueue_ops_sec});
        try w.print("      \"rfc3339_ns\": {d},\n", .{r.rfc3339_ns});
        try w.print("      \"queued_record_ns\": {d},\n", .{r.queued_record_ns});
        try w.print("      \"sensitive_key_ns\": {d}\n", .{r.sensitive_key_ns});

        if (i < results.len - 1) {
            try w.print("    }},\n", .{});
        } else {
            try w.print("    }}\n", .{});
        }
    }

    try w.print("  ]\n", .{});
    try w.print("}}\n", .{});
}

// ============================================================================
// Human-readable Output (stderr)
// ============================================================================

fn printSummary(results: []const TierResult) void {
    const stderr = std.fs.File.stderr().deprecatedWriter();

    stderr.print("\n", .{}) catch {};
    stderr.print("================================================================================\n", .{}) catch {};
    stderr.print("  slogz incremental scale benchmark\n", .{}) catch {};
    stderr.print("================================================================================\n", .{}) catch {};
    stderr.print("\n", .{}) catch {};

    // Header
    stderr.print("  {s:<10} {s:>8} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10}\n", .{
        "Tier",
        "Msgs",
        "Discard",
        "Text",
        "JSON",
        "Multi(3)",
        "Async",
        "Lgr-off",
        "Lgr-on",
    }) catch {};
    stderr.print("  {s:<10} {s:>8} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10}\n", .{
        "----",
        "----",
        "(ops/s)",
        "(ops/s)",
        "(ops/s)",
        "(ops/s)",
        "(ops/s)",
        "(ns/op)",
        "(ns/op)",
    }) catch {};

    for (results) |r| {
        stderr.print("  {s:<10} {d:>8} {d:>10} {d:>10} {d:>10} {d:>10} {d:>10} {d:>10} {d:>10}\n", .{
            r.name,
            r.message_count,
            r.discard_ops_sec,
            r.text_ops_sec,
            r.json_ops_sec,
            r.multi_handler_ops_sec,
            r.async_enqueue_ops_sec,
            r.logger_disabled_ns,
            r.logger_enabled_ns,
        }) catch {};
    }

    stderr.print("\n", .{}) catch {};

    // Formatting sub-table
    stderr.print("  {s:<10} {s:>10} {s:>10} {s:>10}\n", .{
        "Tier",
        "RFC3339",
        "QueueRec",
        "SensKey",
    }) catch {};
    stderr.print("  {s:<10} {s:>10} {s:>10} {s:>10}\n", .{
        "----",
        "(ns/op)",
        "(ns/op)",
        "(ns/op)",
    }) catch {};

    for (results) |r| {
        stderr.print("  {s:<10} {d:>10} {d:>10} {d:>10}\n", .{
            r.name,
            r.rfc3339_ns,
            r.queued_record_ns,
            r.sensitive_key_ns,
        }) catch {};
    }

    stderr.print("\n", .{}) catch {};
    stderr.print("================================================================================\n", .{}) catch {};
}

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Parse args for optional tier filter
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    var tier_filter: ?[]const u8 = null;
    if (args.len > 1) {
        tier_filter = args[1];
    }

    var results_buf: [tiers.len]TierResult = undefined;
    var result_count: usize = 0;

    for (tiers) |tier| {
        if (tier_filter) |filter| {
            if (!std.mem.eql(u8, tier.name, filter)) continue;
        }

        const stderr = std.fs.File.stderr().deprecatedWriter();
        stderr.print("  Running tier {s} ({s})...\n", .{ tier.name, tier.description }) catch {};

        results_buf[result_count] = runTier(tier);
        result_count += 1;
    }

    const results = results_buf[0..result_count];

    if (result_count == 0) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        stderr.print("No tiers matched filter. Available: ", .{}) catch {};
        for (tiers) |tier| {
            stderr.print("{s} ", .{tier.name}) catch {};
        }
        stderr.print("\n", .{}) catch {};
        return;
    }

    // Print human summary to stderr
    printSummary(results);

    // Write JSON to stdout
    try writeJsonResults(results);
}
