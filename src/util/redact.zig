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

/// Returns true if the key should be automatically redacted.
pub fn isSensitiveKey(key: []const u8) bool {
    var lower_buf: [64]u8 = undefined;
    const lower_len = @min(key.len, lower_buf.len);
    for (key[0..lower_len], 0..) |c, i| {
        lower_buf[i] = std.ascii.toLower(c);
    }
    const lower = lower_buf[0..lower_len];

    for (sensitive_keys) |sensitive| {
        if (std.mem.indexOf(u8, lower, sensitive) != null) {
            return true;
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
