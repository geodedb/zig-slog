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
///
/// Patterns are matched as substrings (case-insensitive), so a key like
/// "x_api_key_v2" will match "api_key". The list covers common credential,
/// token, session, and PII key patterns.
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
    "ssn",
    "social_security",
    "credit_card",
    "card_number",
    "cvv",
    "pin",
    "bearer",
    "jwt",
    "cookie",
    "session",
    "session_id",
    "signing_key",
    "encryption_key",
    "client_secret",
    "connection_string",
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
///
/// The check is case-insensitive and matches any key that *contains*
/// one of the following patterns as a substring:
///
///   password, passwd, secret, api_key, apikey, token, auth,
///   authorization, credential, private_key, privatekey, access_key,
///   accesskey, secret_key, secretkey, ssn, social_security,
///   credit_card, card_number, cvv, pin, bearer, jwt, cookie,
///   session, session_id, signing_key, encryption_key, client_secret,
///   connection_string
///
/// For example, `isSensitiveKey("x_api_key_v2")` returns true because
/// it contains "api_key".
///
/// Implementation note: uses a single-pass scan with comptime-unrolled
/// pattern matching for efficient fixed-length comparisons.
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

test "isSensitiveKey expanded patterns" {
    // PII patterns
    try std.testing.expect(isSensitiveKey("ssn"));
    try std.testing.expect(isSensitiveKey("SSN"));
    try std.testing.expect(isSensitiveKey("social_security"));
    try std.testing.expect(isSensitiveKey("credit_card"));
    try std.testing.expect(isSensitiveKey("card_number"));
    try std.testing.expect(isSensitiveKey("cvv"));
    try std.testing.expect(isSensitiveKey("pin"));

    // Token/session patterns
    try std.testing.expect(isSensitiveKey("bearer"));
    try std.testing.expect(isSensitiveKey("BEARER_TOKEN"));
    try std.testing.expect(isSensitiveKey("jwt"));
    try std.testing.expect(isSensitiveKey("JWT_TOKEN"));
    try std.testing.expect(isSensitiveKey("cookie"));
    try std.testing.expect(isSensitiveKey("session"));
    try std.testing.expect(isSensitiveKey("session_id"));

    // Key/secret patterns
    try std.testing.expect(isSensitiveKey("signing_key"));
    try std.testing.expect(isSensitiveKey("encryption_key"));
    try std.testing.expect(isSensitiveKey("client_secret"));
    try std.testing.expect(isSensitiveKey("connection_string"));

    // Should not match
    try std.testing.expect(!isSensitiveKey("hostname"));
    try std.testing.expect(!isSensitiveKey("port"));
    try std.testing.expect(!isSensitiveKey("method"));
}

test "redact" {
    var buf: [32]u8 = undefined;
    const result = redact(&buf, "secret_value");
    try std.testing.expectEqualStrings(REDACTED, result);
}
