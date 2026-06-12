// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! slogz Benchmark Comparison Tool
//!
//! Compares two JSON benchmark result files and detects regressions.
//! Exit code 0 = all pass, 1 = regression detected.
//!
//! Usage:
//!   zig build compare-bench -- baseline.json current.json [threshold_pct]
//!
//! Default threshold: 20% (configurable via third argument)

const std = @import("std");

fn getIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

const Metric = struct {
    name: []const u8,
    json_key: []const u8,
    higher_is_better: bool,
};

const metrics = [_]Metric{
    .{ .name = "Discard ops/s", .json_key = "discard_ops_sec", .higher_is_better = true },
    .{ .name = "Text ops/s", .json_key = "text_ops_sec", .higher_is_better = true },
    .{ .name = "JSON ops/s", .json_key = "json_ops_sec", .higher_is_better = true },
    .{ .name = "Discard ns/op", .json_key = "discard_ns_op", .higher_is_better = false },
    .{ .name = "Text ns/op", .json_key = "text_ns_op", .higher_is_better = false },
    .{ .name = "JSON ns/op", .json_key = "json_ns_op", .higher_is_better = false },
    .{ .name = "Logger disabled ns", .json_key = "logger_disabled_ns", .higher_is_better = false },
    .{ .name = "Logger enabled ns", .json_key = "logger_enabled_ns", .higher_is_better = false },
    .{ .name = "Multi-handler ns", .json_key = "multi_handler_ns", .higher_is_better = false },
    .{ .name = "Multi-handler ops/s", .json_key = "multi_handler_ops_sec", .higher_is_better = true },
    .{ .name = "Async enqueue ns", .json_key = "async_enqueue_ns", .higher_is_better = false },
    .{ .name = "Async enqueue ops/s", .json_key = "async_enqueue_ops_sec", .higher_is_better = true },
    .{ .name = "RFC3339 ns", .json_key = "rfc3339_ns", .higher_is_better = false },
    .{ .name = "QueuedRecord ns", .json_key = "queued_record_ns", .higher_is_better = false },
    .{ .name = "Sensitive key ns", .json_key = "sensitive_key_ns", .higher_is_better = false },
};

const TierValues = struct {
    name: []const u8,
    values: [metrics.len]?i64,
};

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const io = getIo();
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var read_buf: [8192]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    return try reader.interface.allocRemaining(allocator, .limited(10 * 1024 * 1024));
}

const MAX_TIERS = 16;

const TierArray = struct {
    items: [MAX_TIERS]TierValues,
    len: usize,

    fn slice(self: *const TierArray) []const TierValues {
        return self.items[0..self.len];
    }
};

fn extractTiers(content: []const u8) TierArray {
    var result = TierArray{
        .items = undefined,
        .len = 0,
    };

    // Simple JSON parsing: find each tier object between { } in the tiers array
    var pos: usize = 0;

    // Find "tiers" key
    const tiers_start = std.mem.indexOf(u8, content, "\"tiers\"") orelse return result;
    pos = tiers_start;

    // Find opening [
    pos = std.mem.indexOfPos(u8, content, pos, "[") orelse return result;
    pos += 1;

    while (pos < content.len and result.len < MAX_TIERS) {
        // Find next {
        const obj_start = std.mem.indexOfPos(u8, content, pos, "{") orelse break;
        // Find matching }
        const obj_end = std.mem.indexOfPos(u8, content, obj_start + 1, "}") orelse break;
        const obj = content[obj_start .. obj_end + 1];

        var tier = TierValues{
            .name = "",
            .values = .{null} ** metrics.len,
        };

        // Extract name
        if (std.mem.indexOf(u8, obj, "\"name\"")) |name_pos| {
            const colon = std.mem.indexOfPos(u8, obj, name_pos, ":") orelse {
                pos = obj_end + 1;
                continue;
            };
            const quote1 = std.mem.indexOfPos(u8, obj, colon, "\"") orelse {
                pos = obj_end + 1;
                continue;
            };
            const quote2 = std.mem.indexOfPos(u8, obj, quote1 + 1, "\"") orelse {
                pos = obj_end + 1;
                continue;
            };
            tier.name = obj[quote1 + 1 .. quote2];
        }

        // Extract each metric value
        for (&metrics, 0..) |m, i| {
            tier.values[i] = extractIntValue(obj, m.json_key);
        }

        result.items[result.len] = tier;
        result.len += 1;
        pos = obj_end + 1;
    }

    return result;
}

fn extractIntValue(obj: []const u8, key: []const u8) ?i64 {
    // Search for "key": value pattern
    var search_buf: [128]u8 = undefined;
    const search_key = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;

    const key_pos = std.mem.indexOf(u8, obj, search_key) orelse return null;
    const colon = std.mem.indexOfPos(u8, obj, key_pos + search_key.len, ":") orelse return null;

    // Skip whitespace after colon
    var val_start = colon + 1;
    while (val_start < obj.len and (obj[val_start] == ' ' or obj[val_start] == '\t' or obj[val_start] == '\n')) {
        val_start += 1;
    }

    // Read digits
    var val_end = val_start;
    if (val_end < obj.len and obj[val_end] == '-') val_end += 1;
    while (val_end < obj.len and obj[val_end] >= '0' and obj[val_end] <= '9') {
        val_end += 1;
    }

    if (val_end == val_start) return null;

    return std.fmt.parseInt(i64, obj[val_start..val_end], 10) catch null;
}

/// Compares baseline tiers against current tiers and returns the number of
/// per-metric regressions beyond `threshold` percent. When `out` is non-null,
/// a per-metric report is written to it. (PERF-043: extracted from main so the
/// regression gate itself is unit-testable.)
fn compareTiers(
    baseline: []const TierValues,
    current: []const TierValues,
    threshold: f64,
    out: ?*std.Io.Writer,
) !usize {
    var regressions: usize = 0;

    for (baseline) |base_tier| {
        // Find matching tier in current
        const curr_tier = blk: {
            for (current) |ct| {
                if (std.mem.eql(u8, ct.name, base_tier.name)) break :blk ct;
            }
            // A tier missing from current results is itself a regression:
            // a dropped/renamed tier must fail the gate, not silently pass.
            regressions += 1;
            if (out) |w| try w.print("  Tier {s}: MISSING in current results\n\n", .{base_tier.name});
            continue;
        };

        if (out) |w| {
            try w.print("  Tier: {s}\n", .{base_tier.name});
            try w.print("  {s:<25} {s:>12} {s:>12} {s:>8} {s:>6}\n", .{
                "Metric", "Baseline", "Current", "Delta%", "Status",
            });
            try w.print("  {s:<25} {s:>12} {s:>12} {s:>8} {s:>6}\n", .{
                "-------------------------", "------------", "------------", "--------", "------",
            });
        }

        for (&metrics, 0..) |m, i| {
            const base_val = base_tier.values[i] orelse continue;
            const curr_val = curr_tier.values[i] orelse continue;

            if (base_val == 0) continue;

            const delta_pct: f64 = @as(f64, @floatFromInt(curr_val - base_val)) / @as(f64, @floatFromInt(base_val)) * 100.0;

            const is_regression = if (m.higher_is_better)
                delta_pct < -threshold
            else
                delta_pct > threshold;

            if (is_regression) regressions += 1;

            if (out) |w| {
                const status: []const u8 = if (is_regression) "FAIL" else "ok";

                // Format delta with sign manually
                var delta_buf: [16]u8 = undefined;
                const delta_str = std.fmt.bufPrint(&delta_buf, "{d:.1}%", .{delta_pct}) catch "?";

                const base_u: u64 = @intCast(@max(base_val, 0));
                const curr_u: u64 = @intCast(@max(curr_val, 0));

                try w.print("  {s:<25} {d:>12} {d:>12} {s:>8} {s:>6}\n", .{
                    m.name,
                    base_u,
                    curr_u,
                    delta_str,
                    status,
                });
            }
        }

        if (out) |w| try w.print("\n", .{});
    }

    return regressions;
}

pub fn main(init: std.process.Init.Minimal) !void {
    const io = getIo();
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse args
    var args_iter = std.process.Args.Iterator.init(init.args);
    _ = args_iter.next(); // skip program name

    const baseline_path = args_iter.next() orelse {
        var stderr_buf: [4096]u8 = undefined;
        var stderr_fw = std.Io.File.stderr().writer(io, &stderr_buf);
        const stderr = &stderr_fw.interface;
        try stderr.print("Usage: compare-bench <baseline.json> <current.json> [threshold_pct]\n", .{});
        try stderr.print("\nCompares benchmark results and detects regressions.\n", .{});
        try stderr.print("Default threshold: 20%%\n", .{});
        try stderr.flush();
        std.process.exit(2);
    };

    const current_path = args_iter.next() orelse {
        var stderr_buf: [4096]u8 = undefined;
        var stderr_fw = std.Io.File.stderr().writer(io, &stderr_buf);
        const stderr = &stderr_fw.interface;
        try stderr.print("Usage: compare-bench <baseline.json> <current.json> [threshold_pct]\n", .{});
        try stderr.flush();
        std.process.exit(2);
    };

    const threshold: f64 = if (args_iter.next()) |threshold_arg|
        std.fmt.parseFloat(f64, threshold_arg) catch 20.0
    else
        20.0;

    const baseline_content = readFile(allocator, baseline_path) catch |err| {
        var stderr_buf: [4096]u8 = undefined;
        var stderr_fw = std.Io.File.stderr().writer(io, &stderr_buf);
        const stderr = &stderr_fw.interface;
        try stderr.print("Error reading baseline: {s}: {}\n", .{ baseline_path, err });
        try stderr.flush();
        std.process.exit(2);
    };
    defer allocator.free(baseline_content);

    const current_content = readFile(allocator, current_path) catch |err| {
        var stderr_buf: [4096]u8 = undefined;
        var stderr_fw = std.Io.File.stderr().writer(io, &stderr_buf);
        const stderr = &stderr_fw.interface;
        try stderr.print("Error reading current: {s}: {}\n", .{ current_path, err });
        try stderr.flush();
        std.process.exit(2);
    };
    defer allocator.free(current_content);

    const baseline_tiers = extractTiers(baseline_content);
    const current_tiers = extractTiers(current_content);

    var stdout_buf: [8192]u8 = undefined;
    var stdout_fw = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_fw.interface;

    try stdout.print("\n", .{});
    try stdout.print("================================================================================\n", .{});
    try stdout.print("  slogz benchmark comparison (threshold: {d:.0}%)\n", .{threshold});
    try stdout.print("================================================================================\n", .{});
    try stdout.print("\n", .{});

    const regressions = try compareTiers(baseline_tiers.slice(), current_tiers.slice(), threshold, stdout);

    try stdout.print("================================================================================\n", .{});

    if (regressions > 0) {
        try stdout.print("  RESULT: REGRESSION DETECTED (threshold: {d:.0}%)\n", .{threshold});
        try stdout.print("================================================================================\n", .{});
        try stdout.flush();
        std.process.exit(1);
    } else {
        try stdout.print("  RESULT: ALL PASS (threshold: {d:.0}%)\n", .{threshold});
        try stdout.print("================================================================================\n", .{});
        try stdout.flush();
    }
}

// ---------------------------------------------------------------------------
// Self-tests (PERF-043): the regression gate must not silently re-break.
// Fixture shape mirrors benchmarks/results/baseline.json: a "tiers" array of
// objects with "name" and metric keys from the `metrics` table above.
// ---------------------------------------------------------------------------

const fixture_base =
    \\{"tiers":[{"name":"100K","text_ns_op":100,"json_ns_op":100}]}
;
const fixture_regressed =
    \\{"tiers":[{"name":"100K","text_ns_op":200,"json_ns_op":100}]}
;

test "extractTiers parses tier name and metric values" {
    const tiers = extractTiers(fixture_base);
    try std.testing.expectEqual(@as(usize, 1), tiers.len);
    try std.testing.expectEqualStrings("100K", tiers.items[0].name);

    var saw_text_ns_op = false;
    for (&metrics, 0..) |m, i| {
        if (std.mem.eql(u8, m.json_key, "text_ns_op")) {
            try std.testing.expectEqual(@as(?i64, 100), tiers.items[0].values[i]);
            saw_text_ns_op = true;
        }
    }
    try std.testing.expect(saw_text_ns_op);
}

test "compare detects regression beyond threshold" {
    const base = extractTiers(fixture_base);
    const curr = extractTiers(fixture_regressed);
    // text_ns_op: 100 -> 200 is a 100% regression against a 20% threshold.
    try std.testing.expect(try compareTiers(base.slice(), curr.slice(), 20.0, null) > 0);
}

test "compare passes identical results" {
    const base = extractTiers(fixture_base);
    const curr = extractTiers(fixture_base);
    try std.testing.expectEqual(@as(usize, 0), try compareTiers(base.slice(), curr.slice(), 20.0, null));
}

test "compare counts missing tier as regression" {
    const base = extractTiers(fixture_base);
    const curr = extractTiers("{\"tiers\":[]}");
    // A tier dropped from current results must fail the gate, not pass silently.
    try std.testing.expect(try compareTiers(base.slice(), curr.slice(), 20.0, null) > 0);
}

const fixture_ops_base =
    \\{"tiers":[{"name":"100K","text_ops_sec":1000}]}
;
const fixture_ops_regressed =
    \\{"tiers":[{"name":"100K","text_ops_sec":500}]}
;

test "compare detects ops/s regression (higher_is_better)" {
    const base = extractTiers(fixture_ops_base);
    const curr = extractTiers(fixture_ops_regressed);
    // text_ops_sec is higher_is_better: 1000 -> 500 is a -50% delta against
    // a 20% threshold, exercising the delta_pct < -threshold branch.
    try std.testing.expect(try compareTiers(base.slice(), curr.slice(), 20.0, null) > 0);
}
