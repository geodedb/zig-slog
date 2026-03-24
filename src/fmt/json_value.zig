// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Shared JSON value serialization for all JSON-emitting handlers and sinks.
//!
//! This module provides the canonical `writeJsonValue` function used by
//! json_handler, tcp_sink, udp_sink, and http_sink to serialize `Value`
//! instances into a JSON streaming encoder.

const std = @import("std");
const Value = @import("../value.zig").Value;
const redact = @import("../util/redact.zig");

/// Write a `Value` as JSON into a streaming encoder.
///
/// The encoder (`enc`) must support writeString, writeInt, writeFloat,
/// writeBool, and writeNull (i.e., the interface returned by
/// `json.streamingEncoder`).
pub fn writeJsonValue(enc: anytype, value: Value) !void {
    switch (value) {
        .str => |s| enc.writeString(s) catch return error.WriteFailed,
        .i64 => |i| enc.writeInt(i) catch return error.WriteFailed,
        .u64 => |u| enc.writeInt(u) catch return error.WriteFailed,
        .f64 => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                enc.writeNull() catch return error.WriteFailed;
            } else {
                enc.writeFloat(f) catch return error.WriteFailed;
            }
        },
        .bool => |b| enc.writeBool(b) catch return error.WriteFailed,
        .secret => enc.writeString(redact.REDACTED) catch return error.WriteFailed,
        .err => |e| {
            const raw: u16 = @intFromError(e);
            if (raw == 0) {
                enc.writeString("error(0)") catch return error.WriteFailed;
            } else {
                enc.writeString(@errorName(e)) catch return error.WriteFailed;
            }
        },
        .bytes => |bytes| {
            var hex_buf: [512]u8 = undefined;
            var hex_len: usize = 0;
            const hex_chars = "0123456789abcdef";
            for (bytes) |byte| {
                if (hex_len + 2 > hex_buf.len) break;
                hex_buf[hex_len] = hex_chars[byte >> 4];
                hex_buf[hex_len + 1] = hex_chars[byte & 0x0f];
                hex_len += 2;
            }
            enc.writeString(hex_buf[0..hex_len]) catch return error.WriteFailed;
        },
        .marshaler => enc.writeNull() catch return error.WriteFailed,
    }
}
