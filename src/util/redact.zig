// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Redaction utilities for sensitive values.
//!
//! Provides safe handling of secrets in log output.

const std = @import("std");
const Secret = @import("../value.zig").Secret;

/// Default redaction marker.
pub const REDACTED = "[REDACTED]";

/// List of keys that should be automatically redacted.
pub const sensitive_keys = [_][]const u8{
    "password",
    "passwd",
    "secret",
    "api_key",
    "apikey",
    "token",
    "auth",
    "authorization",
    "credential",
    "private_key",
    "privatekey",
    "access_key",
    "accesskey",
    "secret_key",
    "secretkey",
};

/// Minimum pattern length, computed at comptime for fast rejection.
const min_pattern_len = blk: {
    var min: usize = sensitive_keys[0].len;
    for (sensitive_keys) |k| {
        if (k.len < min) min = k.len;
    }
    break :blk min;
};

/// Returns true if the key should be automatically redacted.
/// Uses a single-pass scan with comptime-unrolled pattern matching
/// instead of 15 separate indexOf calls.
pub fn isSensitiveKey(key: []const u8) bool {
    if (key.len < min_pattern_len) return false;

    var lower_buf: [64]u8 = undefined;
    const lower_len = @min(key.len, lower_buf.len);
    for (key[0..lower_len], 0..) |c, i| {
        lower_buf[i] = std.ascii.toLower(c);
    }
    const lower = lower_buf[0..lower_len];

    // Single-pass scan: at each position, check all patterns via inline for.
    // The compiler unrolls each pattern check at comptime, enabling optimized
    // fixed-length comparisons.
    for (0..lower.len) |pos| {
        const remaining = lower.len - pos;
        inline for (sensitive_keys) |pattern| {
            if (remaining >= pattern.len and
                std.mem.eql(u8, lower[pos..][0..pattern.len], pattern))
            {
                return true;
            }
        }
    }
    return false;
}

/// Redacts a value, replacing with REDACTED marker.
pub fn redact(output: []u8, _: []const u8) []const u8 {
    const len = @min(REDACTED.len, output.len);
    @memcpy(output[0..len], REDACTED[0..len]);
    return output[0..len];
}

/// Returns the redacted representation of a secret.
pub fn redactSecret(_: Secret) []const u8 {
    return REDACTED;
}

test "isSensitiveKey" {
    try std.testing.expect(isSensitiveKey("password"));
    try std.testing.expect(isSensitiveKey("PASSWORD"));
    try std.testing.expect(isSensitiveKey("user_password"));
    try std.testing.expect(isSensitiveKey("api_key"));
    try std.testing.expect(!isSensitiveKey("username"));
    try std.testing.expect(!isSensitiveKey("email"));
}

test "redact" {
    var buf: [32]u8 = undefined;
    const result = redact(&buf, "secret_value");
    try std.testing.expectEqualStrings(REDACTED, result);
}
