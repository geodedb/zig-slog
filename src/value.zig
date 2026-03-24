// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Value types for structured logging attributes.
//!
//! Values support various primitive types plus special types like Secret
//! for redaction and Marshaler for custom serialization.

const std = @import("std");
const redact_util = @import("util/redact.zig");

/// A secret value that will be redacted in log output.
///
/// Note: The secret value is stored in plaintext in process memory.
/// It is only redacted during serialization. Consider memory scrubbing
/// in security-sensitive deployments.
pub const Secret = struct {
    value: []const u8,

    pub fn init(v: []const u8) Secret {
        return .{ .value = v };
    }

    /// Returns the redacted representation.
    pub fn redacted() []const u8 {
        return redact_util.REDACTED;
    }
};

/// Interface for custom value marshaling.
pub const Marshaler = struct {
    ctx: ?*anyopaque,
    marshalFn: *const fn (ctx: ?*anyopaque, allocator: std.mem.Allocator) MarshalError![]Attr,

    pub const MarshalError = error{
        OutOfMemory,
        InvalidData,
    };

    pub fn marshalAttrs(self: *const Marshaler, allocator: std.mem.Allocator) MarshalError![]Attr {
        return self.marshalFn(self.ctx, allocator);
    }
};

/// A structured logging attribute (key-value pair).
pub const Attr = struct {
    key: []const u8,
    value: Value,

    /// Creates a string attribute.
    pub fn string(key: []const u8, val: []const u8) Attr {
        return .{ .key = key, .value = .{ .str = val } };
    }

    /// Creates an i64 attribute.
    pub fn int(key: []const u8, val: i64) Attr {
        return .{ .key = key, .value = .{ .i64 = val } };
    }

    /// Creates a u64 attribute.
    pub fn uint(key: []const u8, val: u64) Attr {
        return .{ .key = key, .value = .{ .u64 = val } };
    }

    /// Creates a float attribute.
    pub fn float(key: []const u8, val: f64) Attr {
        return .{ .key = key, .value = .{ .f64 = val } };
    }

    /// Creates a boolean attribute.
    pub fn boolean(key: []const u8, val: bool) Attr {
        return .{ .key = key, .value = .{ .bool = val } };
    }

    /// Creates a bytes attribute.
    pub fn bytes(key: []const u8, val: []const u8) Attr {
        return .{ .key = key, .value = .{ .bytes = val } };
    }

    /// Creates an error attribute.
    pub fn err(key: []const u8, val: anyerror) Attr {
        return .{ .key = key, .value = .{ .err = val } };
    }

    /// Creates a secret attribute (will be redacted in all handler output).
    ///
    /// The value is replaced with "[REDACTED]" during serialization by every
    /// handler. Note that only structured attribute values are redacted --
    /// the `message` field of a log record is NOT scanned for secrets.
    /// Never embed sensitive data directly in message strings; use this
    /// method instead to ensure automatic redaction.
    pub fn secret(key: []const u8, val: []const u8) Attr {
        return .{ .key = key, .value = .{ .secret = Secret.init(val) } };
    }

    /// Creates a marshaler attribute.
    pub fn marshaler(key: []const u8, val: *const Marshaler) Attr {
        return .{ .key = key, .value = .{ .marshaler = val } };
    }

    /// Creates a duration attribute (nanoseconds displayed as human-readable).
    pub fn duration(key: []const u8, nanos: i64) Attr {
        return .{ .key = key, .value = .{ .i64 = nanos } };
    }
};

/// A value that can be associated with an attribute key.
pub const Value = union(enum) {
    i64: i64,
    u64: u64,
    f64: f64,
    bool: bool,
    str: []const u8,
    bytes: []const u8,
    err: anyerror,
    secret: Secret,
    marshaler: *const Marshaler,

    /// Returns true if the value is valid for JSON output.
    /// NaN and Inf are not valid JSON numbers.
    pub fn isValidJson(self: Value) bool {
        return switch (self) {
            .f64 => |f| !std.math.isNan(f) and !std.math.isInf(f),
            else => true,
        };
    }

    /// Returns the size estimate for this value when serialized.
    pub fn estimatedSize(self: Value) usize {
        return switch (self) {
            .i64 => 20, // max i64 digits
            .u64 => 20,
            .f64 => 24,
            .bool => 5, // "false"
            .str => |s| s.len + 2, // quotes
            .bytes => |b| b.len * 2 + 2, // hex + quotes
            .err => 64,
            .secret => Secret.redacted().len + 2,
            .marshaler => 256, // estimate
        };
    }
};

test "Attr.string" {
    const a = Attr.string("key", "value");
    try std.testing.expectEqualStrings("key", a.key);
    try std.testing.expectEqualStrings("value", a.value.str);
}

test "Value.isValidJson" {
    try std.testing.expect((Value{ .f64 = 1.5 }).isValidJson());
    try std.testing.expect(!(Value{ .f64 = std.math.nan(f64) }).isValidJson());
    try std.testing.expect(!(Value{ .f64 = std.math.inf(f64) }).isValidJson());
}
