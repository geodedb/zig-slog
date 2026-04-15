// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Shared text value serialization for all text-mode handlers.
//!
//! This module provides the canonical `writeTextValue` function used by
//! text_handler, journald, windows_eventlog, and rotating_file to serialize
//! `Value` instances into a human-readable text writer.
//!
//! Canonical behavior choices:
//! - Float precision: `{d:.6}` (6 decimal places for consistency)
//! - Bytes encoding: `0x` prefix + hex lookup table
//! - String sanitization: `sanitize.sanitizeOutput()` (no quoting; handlers
//!   that need quoting should wrap this function)
//! - Marshaler text: `<marshaler>` (descriptive)
//! - Error guard: raw-value check before `@errorName` to prevent UB on corrupt values

const std = @import("std");
const Value = @import("../value.zig").Value;
const redact = @import("../util/redact.zig");
const sanitize = @import("../util/sanitize.zig");

/// Write a `Value` as human-readable text.
///
/// The `writer` can be any type supporting the standard writer interface
/// (writeAll, writeByte, print).
pub fn writeTextValue(writer: anytype, value: Value) !void {
    switch (value) {
        .str => |s| try sanitize.sanitizeOutput(writer, s),
        .i64 => |i| try writer.print("{d}", .{i}),
        .u64 => |u| try writer.print("{d}", .{u}),
        .f64 => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                try writer.writeAll("null");
            } else {
                try writer.print("{d:.6}", .{f});
            }
        },
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .bytes => |b| {
            try writer.writeAll("0x");
            const hex_chars = "0123456789abcdef";
            for (b) |byte| {
                try writer.writeAll(&[2]u8{ hex_chars[byte >> 4], hex_chars[byte & 0x0f] });
            }
        },
        .err => |e| {
            const raw: u16 = @intFromError(e);
            if (raw == 0) {
                try writer.writeAll("error(0)");
            } else {
                try writer.writeAll(@errorName(e));
            }
        },
        .secret => try writer.writeAll(redact.REDACTED),
        .marshaler => try writer.writeAll("<marshaler>"),
    }
}

// --- Tests ---

test "writeTextValue str" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .str = "hello world" });
    try std.testing.expectEqualStrings("hello world", fbs.buffered());
}

test "writeTextValue str sanitizes control chars" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .str = "line1\nline2" });
    try std.testing.expectEqualStrings("line1\\nline2", fbs.buffered());
}

test "writeTextValue i64" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .i64 = -42 });
    try std.testing.expectEqualStrings("-42", fbs.buffered());
}

test "writeTextValue u64" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .u64 = 1000 });
    try std.testing.expectEqualStrings("1000", fbs.buffered());
}

test "writeTextValue f64" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .f64 = 3.14 });
    try std.testing.expect(std.mem.indexOf(u8, fbs.buffered(), "3.14") != null);
}

test "writeTextValue f64 NaN" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .f64 = std.math.nan(f64) });
    try std.testing.expectEqualStrings("null", fbs.buffered());
}

test "writeTextValue f64 Inf" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .f64 = std.math.inf(f64) });
    try std.testing.expectEqualStrings("null", fbs.buffered());
}

test "writeTextValue bool" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .bool = true });
    try std.testing.expectEqualStrings("true", fbs.buffered());

    fbs.end = 0;
    try writeTextValue(&fbs, Value{ .bool = false });
    try std.testing.expectEqualStrings("false", fbs.buffered());
}

test "writeTextValue bytes" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .bytes = &[_]u8{ 0xde, 0xad, 0xbe, 0xef } });
    try std.testing.expectEqualStrings("0xdeadbeef", fbs.buffered());
}

test "writeTextValue err" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .err = error.OutOfMemory });
    try std.testing.expectEqualStrings("OutOfMemory", fbs.buffered());
}

test "writeTextValue secret" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    try writeTextValue(&fbs, Value{ .secret = @import("../value.zig").Secret.init("hidden") });
    try std.testing.expectEqualStrings("[REDACTED]", fbs.buffered());
}

test "writeTextValue marshaler" {
    var buf: [256]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);
    // Create a dummy marshaler pointer for testing
    const m = @import("../value.zig").Marshaler{
        .ctx = null,
        .marshalFn = undefined,
    };
    try writeTextValue(&fbs, Value{ .marshaler = &m });
    try std.testing.expectEqualStrings("<marshaler>", fbs.buffered());
}
