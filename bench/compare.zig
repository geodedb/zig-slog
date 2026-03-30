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
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("Usage: compare-bench <baseline.json> <current.json> [threshold_pct]\n", .{});
        try stderr.print("\nCompares benchmark results and detects regressions.\n", .{});
        try stderr.print("Default threshold: 20%%\n", .{});
        std.process.exit(2);
    }

    const baseline_path = args[1];
    const current_path = args[2];
    const threshold: f64 = if (args.len > 3)
        std.fmt.parseFloat(f64, args[3]) catch 20.0
    else
        20.0;

    const baseline_content = readFile(allocator, baseline_path) catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("Error reading baseline: {s}: {}\n", .{ baseline_path, err });
        std.process.exit(2);
    };
    defer allocator.free(baseline_content);

    const current_content = readFile(allocator, current_path) catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("Error reading current: {s}: {}\n", .{ current_path, err });
        std.process.exit(2);
    };
    defer allocator.free(current_content);

    const baseline_tiers = extractTiers(baseline_content);
    const current_tiers = extractTiers(current_content);

    const stdout = std.fs.File.stdout().deprecatedWriter();

    try stdout.print("\n", .{});
    try stdout.print("================================================================================\n", .{});
    try stdout.print("  slogz benchmark comparison (threshold: {d:.0}%)\n", .{threshold});
    try stdout.print("================================================================================\n", .{});
    try stdout.print("\n", .{});

    var any_regression = false;

    for (baseline_tiers.slice()) |base_tier| {
        // Find matching tier in current
        const curr_tier = blk: {
            for (current_tiers.slice()) |ct| {
                if (std.mem.eql(u8, ct.name, base_tier.name)) break :blk ct;
            }
            try stdout.print("  Tier {s}: MISSING in current results\n\n", .{base_tier.name});
            continue;
        };

        try stdout.print("  Tier: {s}\n", .{base_tier.name});
        try stdout.print("  {s:<25} {s:>12} {s:>12} {s:>8} {s:>6}\n", .{
            "Metric", "Baseline", "Current", "Delta%", "Status",
        });
        try stdout.print("  {s:<25} {s:>12} {s:>12} {s:>8} {s:>6}\n", .{
            "-------------------------", "------------", "------------", "--------", "------",
        });

        for (&metrics, 0..) |m, i| {
            const base_val = base_tier.values[i] orelse continue;
            const curr_val = curr_tier.values[i] orelse continue;

            if (base_val == 0) continue;

            const delta_pct: f64 = @as(f64, @floatFromInt(curr_val - base_val)) / @as(f64, @floatFromInt(base_val)) * 100.0;

            const is_regression = if (m.higher_is_better)
                delta_pct < -threshold
            else
                delta_pct > threshold;

            const status: []const u8 = if (is_regression) "FAIL" else "ok";

            if (is_regression) any_regression = true;

            // Format delta with sign manually
            var delta_buf: [16]u8 = undefined;
            const delta_str = std.fmt.bufPrint(&delta_buf, "{d:.1}%", .{delta_pct}) catch "?";

            const base_u: u64 = @intCast(@max(base_val, 0));
            const curr_u: u64 = @intCast(@max(curr_val, 0));

            try stdout.print("  {s:<25} {d:>12} {d:>12} {s:>8} {s:>6}\n", .{
                m.name,
                base_u,
                curr_u,
                delta_str,
                status,
            });
        }

        try stdout.print("\n", .{});
    }

    try stdout.print("================================================================================\n", .{});

    if (any_regression) {
        try stdout.print("  RESULT: REGRESSION DETECTED (threshold: {d:.0}%)\n", .{threshold});
        try stdout.print("================================================================================\n", .{});
        std.process.exit(1);
    } else {
        try stdout.print("  RESULT: ALL PASS (threshold: {d:.0}%)\n", .{threshold});
        try stdout.print("================================================================================\n", .{});
    }
}
