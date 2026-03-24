// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Key and string sanitization utilities.
//!
//! Ensures keys are safe for structured output and strings are valid UTF-8.

const std = @import("std");

/// Maximum key length.
pub const MAX_KEY_LENGTH = 64;

/// Sanitizes a key for safe use in structured output.
/// - Replaces invalid characters with '_'
/// - Truncates to MAX_KEY_LENGTH
/// - Returns the sanitized key in the provided buffer
pub fn sanitizeKey(buf: *[MAX_KEY_LENGTH]u8, key: []const u8) []const u8 {
    const len = @min(key.len, MAX_KEY_LENGTH);
    for (key[0..len], 0..) |c, i| {
        if (isValidKeyChar(c)) {
            buf[i] = c;
        } else {
            buf[i] = '_';
        }
    }
    return buf[0..len];
}

/// Returns true if character is valid for a key.
fn isValidKeyChar(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '_', '-', '.' => true,
        else => false,
    };
}

/// Validates that a key contains only allowed characters.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > MAX_KEY_LENGTH) return false;
    for (key) |c| {
        if (!isValidKeyChar(c)) return false;
    }
    return true;
}

/// Replaces invalid UTF-8 sequences with the replacement character.
/// Returns the number of bytes written to the output buffer.
pub fn sanitizeUtf8(output: []u8, input: []const u8) usize {
    var out_pos: usize = 0;
    var in_pos: usize = 0;

    while (in_pos < input.len and out_pos < output.len) {
        const byte = input[in_pos];

        if (byte < 0x80) {
            // ASCII
            output[out_pos] = byte;
            out_pos += 1;
            in_pos += 1;
        } else if (byte < 0xC0) {
            // Invalid continuation byte at start
            if (out_pos + 3 <= output.len) {
                // UTF-8 replacement character: 0xEF 0xBF 0xBD
                output[out_pos] = 0xEF;
                output[out_pos + 1] = 0xBF;
                output[out_pos + 2] = 0xBD;
                out_pos += 3;
            } else break;
            in_pos += 1;
        } else {
            // Multi-byte sequence
            const seq_len: usize = if (byte < 0xE0) 2 else if (byte < 0xF0) 3 else if (byte < 0xF8) 4 else 1;

            if (in_pos + seq_len <= input.len and isValidUtf8Sequence(input[in_pos..][0..seq_len])) {
                if (out_pos + seq_len <= output.len) {
                    @memcpy(output[out_pos..][0..seq_len], input[in_pos..][0..seq_len]);
                    out_pos += seq_len;
                } else break;
                in_pos += seq_len;
            } else {
                // Invalid sequence, emit replacement
                if (out_pos + 3 <= output.len) {
                    output[out_pos] = 0xEF;
                    output[out_pos + 1] = 0xBF;
                    output[out_pos + 2] = 0xBD;
                    out_pos += 3;
                } else break;
                in_pos += 1;
            }
        }
    }

    return out_pos;
}

fn isValidUtf8Sequence(seq: []const u8) bool {
    if (seq.len == 0) return false;

    const first = seq[0];
    if (first < 0x80) return seq.len == 1;
    if (first < 0xC0) return false; // Invalid first byte

    const expected_len: usize = if (first < 0xE0) 2 else if (first < 0xF0) 3 else if (first < 0xF8) 4 else return false;

    if (seq.len < expected_len) return false;

    // Check continuation bytes
    for (seq[1..expected_len]) |b| {
        if (b < 0x80 or b >= 0xC0) return false;
    }

    return true;
}

/// Truncates a string to max_len, adding "..." if truncated.
/// Returns the truncated string in the provided buffer.
pub fn truncate(buf: []u8, input: []const u8, max_len: usize) []const u8 {
    if (input.len <= max_len) {
        const len = @min(input.len, buf.len);
        @memcpy(buf[0..len], input[0..len]);
        return buf[0..len];
    }

    if (max_len <= 3 or buf.len < max_len) {
        const len = @min(input.len, buf.len);
        @memcpy(buf[0..len], input[0..len]);
        return buf[0..len];
    }

    const text_len = max_len - 3;
    @memcpy(buf[0..text_len], input[0..text_len]);
    buf[text_len] = '.';
    buf[text_len + 1] = '.';
    buf[text_len + 2] = '.';
    return buf[0..max_len];
}

/// Sanitizes output by replacing control characters with escape sequences.
/// Prevents log injection via newlines and other control characters.
pub fn sanitizeOutput(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => {
                try writer.print("\\x{x:0>2}", .{c});
            },
            else => try writer.writeByte(c),
        }
    }
}

test "sanitizeOutput" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Normal text passes through
    try sanitizeOutput(writer, "hello world");
    try std.testing.expectEqualStrings("hello world", fbs.getWritten());

    // Reset
    fbs.reset();

    // Newlines are escaped
    try sanitizeOutput(writer, "line1\nline2\rline3");
    try std.testing.expectEqualStrings("line1\\nline2\\rline3", fbs.getWritten());

    // Reset
    fbs.reset();

    // Tab is escaped
    try sanitizeOutput(writer, "key\tvalue");
    try std.testing.expectEqualStrings("key\\tvalue", fbs.getWritten());

    // Reset
    fbs.reset();

    // NUL byte is escaped
    try sanitizeOutput(writer, "before\x00after");
    try std.testing.expectEqualStrings("before\\x00after", fbs.getWritten());
}

test "sanitizeKey" {
    var buf: [MAX_KEY_LENGTH]u8 = undefined;

    const key1 = sanitizeKey(&buf, "valid_key-123");
    try std.testing.expectEqualStrings("valid_key-123", key1);

    const key2 = sanitizeKey(&buf, "invalid key!");
    try std.testing.expectEqualStrings("invalid_key_", key2);
}

test "isValidKey" {
    try std.testing.expect(isValidKey("valid_key"));
    try std.testing.expect(isValidKey("valid-key.123"));
    try std.testing.expect(!isValidKey("invalid key"));
    try std.testing.expect(!isValidKey(""));
}

test "sanitizeUtf8" {
    var buf: [64]u8 = undefined;

    // Valid ASCII
    const len1 = sanitizeUtf8(&buf, "hello");
    try std.testing.expectEqualStrings("hello", buf[0..len1]);

    // Valid UTF-8
    const len2 = sanitizeUtf8(&buf, "hello\xC3\xA9"); // é
    try std.testing.expectEqual(@as(usize, 7), len2);
}

test "truncate" {
    var buf: [64]u8 = undefined;

    const t1 = truncate(&buf, "short", 10);
    try std.testing.expectEqualStrings("short", t1);

    const t2 = truncate(&buf, "this is a long string", 10);
    try std.testing.expectEqualStrings("this is...", t2);
}
