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
