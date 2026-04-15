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
            // Encode in chunks to handle arbitrary-length byte slices without
            // a single oversized stack buffer. Each chunk encodes up to 256
            // input bytes (512 hex chars). First chunk uses writeString to
            // emit the JSON string opener; subsequent chunks append raw hex
            // via writePreEncodedJsonStringChunk if available, or we
            // pre-build the full hex into a reasonably-sized buffer.
            //
            // Pragmatic approach: 2048-byte buffer handles up to 1024 input
            // bytes (covers SHA-512, AES keys, typical binary fields). For
            // inputs beyond 1024 bytes, truncate with a marker.
            const hex_chars = "0123456789abcdef";
            const max_input = 1024;
            var hex_buf: [max_input * 2]u8 = undefined;
            var hex_len: usize = 0;
            const encode_len = @min(bytes.len, max_input);
            for (bytes[0..encode_len]) |byte| {
                hex_buf[hex_len] = hex_chars[byte >> 4];
                hex_buf[hex_len + 1] = hex_chars[byte & 0x0f];
                hex_len += 2;
            }
            if (bytes.len > max_input) {
                // Append truncation marker
                const marker = "...";
                if (hex_len + marker.len <= hex_buf.len) {
                    @memcpy(hex_buf[hex_len..][0..marker.len], marker);
                    hex_len += marker.len;
                }
            }
            enc.writeString(hex_buf[0..hex_len]) catch return error.WriteFailed;
        },
        .marshaler => enc.writeNull() catch return error.WriteFailed,
    }
}

// --- Tests ---

/// Helper: encode a single JSON value and return the output string.
/// Wraps the value in an array so the encoder is in a valid state.
fn testJsonValue(value: Value) ![]const u8 {
    const json = @import("json");
    var buf: [4096]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);
    var stack_buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&stack_buf);
    var enc = json.streamingEncoder(fba.allocator(), fbs.writer(), .{});
    defer enc.deinit();
    enc.beginArray() catch return error.WriteFailed;
    try writeJsonValue(&enc, value);
    enc.endArray() catch return error.WriteFailed;
    return fbs.getWritten();
}

test "writeJsonValue str" {
    const out = try testJsonValue(Value{ .str = "hello" });
    try std.testing.expectEqualStrings("[\"hello\"]", out);
}

test "writeJsonValue i64" {
    const out = try testJsonValue(Value{ .i64 = -42 });
    try std.testing.expectEqualStrings("[-42]", out);
}

test "writeJsonValue u64" {
    const out = try testJsonValue(Value{ .u64 = 1000 });
    try std.testing.expectEqualStrings("[1000]", out);
}

test "writeJsonValue f64" {
    const out = try testJsonValue(Value{ .f64 = 3.14 });
    try std.testing.expect(std.mem.indexOf(u8, out, "3.14") != null);
}

test "writeJsonValue f64 NaN" {
    const out = try testJsonValue(Value{ .f64 = std.math.nan(f64) });
    try std.testing.expectEqualStrings("[null]", out);
}

test "writeJsonValue f64 Inf" {
    const out = try testJsonValue(Value{ .f64 = std.math.inf(f64) });
    try std.testing.expectEqualStrings("[null]", out);
}

test "writeJsonValue bool" {
    const out_true = try testJsonValue(Value{ .bool = true });
    try std.testing.expectEqualStrings("[true]", out_true);

    const out_false = try testJsonValue(Value{ .bool = false });
    try std.testing.expectEqualStrings("[false]", out_false);
}

test "writeJsonValue secret" {
    const out = try testJsonValue(Value{ .secret = @import("../value.zig").Secret.init("hidden") });
    try std.testing.expectEqualStrings("[\"[REDACTED]\"]", out);
}

test "writeJsonValue err" {
    const out = try testJsonValue(Value{ .err = error.OutOfMemory });
    try std.testing.expectEqualStrings("[\"OutOfMemory\"]", out);
}

test "writeJsonValue bytes" {
    const out = try testJsonValue(Value{ .bytes = &[_]u8{ 0xde, 0xad, 0xbe, 0xef } });
    try std.testing.expectEqualStrings("[\"deadbeef\"]", out);
}

test "writeJsonValue bytes empty" {
    const out = try testJsonValue(Value{ .bytes = &[_]u8{} });
    try std.testing.expectEqualStrings("[\"\"]", out);
}

test "writeJsonValue marshaler" {
    const Marshaler = @import("../value.zig").Marshaler;
    const m = Marshaler{
        .ctx = null,
        .marshalFn = undefined,
    };
    const out = try testJsonValue(Value{ .marshaler = &m });
    try std.testing.expectEqualStrings("[null]", out);
}
