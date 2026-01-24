//! Comprehensive unit tests for Value and Attr modules.

const std = @import("std");
const slogz = @import("slogz");
const Value = slogz.Value;
const Attr = slogz.Attr;
const Secret = slogz.Secret;

// ============================================================================
// Value Type Tests
// ============================================================================

test "Value.str" {
    const v = Value{ .str = "hello" };
    try std.testing.expect(v == .str);
    try std.testing.expectEqualStrings("hello", v.str);
}

test "Value.i64" {
    const v = Value{ .i64 = -42 };
    try std.testing.expect(v == .i64);
    try std.testing.expectEqual(@as(i64, -42), v.i64);
}

test "Value.i64 - boundaries" {
    const min_val = Value{ .i64 = std.math.minInt(i64) };
    const max_val = Value{ .i64 = std.math.maxInt(i64) };
    try std.testing.expectEqual(std.math.minInt(i64), min_val.i64);
    try std.testing.expectEqual(std.math.maxInt(i64), max_val.i64);
}

test "Value.u64" {
    const v = Value{ .u64 = 42 };
    try std.testing.expect(v == .u64);
    try std.testing.expectEqual(@as(u64, 42), v.u64);
}

test "Value.u64 - boundaries" {
    const min_val = Value{ .u64 = 0 };
    const max_val = Value{ .u64 = std.math.maxInt(u64) };
    try std.testing.expectEqual(@as(u64, 0), min_val.u64);
    try std.testing.expectEqual(std.math.maxInt(u64), max_val.u64);
}

test "Value.f64" {
    const v = Value{ .f64 = 3.14159 };
    try std.testing.expect(v == .f64);
    try std.testing.expectApproxEqRel(@as(f64, 3.14159), v.f64, 0.0001);
}

test "Value.f64 - special values" {
    const nan = Value{ .f64 = std.math.nan(f64) };
    const inf = Value{ .f64 = std.math.inf(f64) };
    const neg_inf = Value{ .f64 = -std.math.inf(f64) };

    try std.testing.expect(std.math.isNan(nan.f64));
    try std.testing.expect(std.math.isInf(inf.f64));
    try std.testing.expect(std.math.isNegativeInf(neg_inf.f64));
}

test "Value.bool" {
    const true_val = Value{ .bool = true };
    const false_val = Value{ .bool = false };
    try std.testing.expect(true_val == .bool);
    try std.testing.expect(true_val.bool == true);
    try std.testing.expect(false_val.bool == false);
}

test "Value.bytes" {
    const data = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    const v = Value{ .bytes = &data };
    try std.testing.expect(v == .bytes);
    try std.testing.expectEqualSlices(u8, &data, v.bytes);
}

test "Value.err" {
    const v = Value{ .err = error.OutOfMemory };
    try std.testing.expect(v == .err);
    try std.testing.expectEqual(error.OutOfMemory, v.err);
}

test "Value.secret" {
    const s = Secret{ .value = "my-secret" };
    const v = Value{ .secret = s };
    try std.testing.expect(v == .secret);
    try std.testing.expectEqualStrings("my-secret", v.secret.value);
}

// ============================================================================
// Value JSON Validation Tests
// ============================================================================

test "Value.isValidJson - valid numbers" {
    try std.testing.expect((Value{ .i64 = 0 }).isValidJson());
    try std.testing.expect((Value{ .u64 = 0 }).isValidJson());
    try std.testing.expect((Value{ .f64 = 0.0 }).isValidJson());
    try std.testing.expect((Value{ .f64 = 1.5 }).isValidJson());
}

test "Value.isValidJson - invalid floats" {
    try std.testing.expect(!(Value{ .f64 = std.math.nan(f64) }).isValidJson());
    try std.testing.expect(!(Value{ .f64 = std.math.inf(f64) }).isValidJson());
    try std.testing.expect(!(Value{ .f64 = -std.math.inf(f64) }).isValidJson());
}

test "Value.isValidJson - other types always valid" {
    try std.testing.expect((Value{ .str = "test" }).isValidJson());
    try std.testing.expect((Value{ .bool = true }).isValidJson());
    try std.testing.expect((Value{ .err = error.Test }).isValidJson());
}

// ============================================================================
// Attr Constructor Tests
// ============================================================================

test "Attr.string" {
    const attr = Attr.string("key", "value");
    try std.testing.expectEqualStrings("key", attr.key);
    try std.testing.expect(attr.value == .str);
    try std.testing.expectEqualStrings("value", attr.value.str);
}

test "Attr.int" {
    const attr = Attr.int("count", -100);
    try std.testing.expectEqualStrings("count", attr.key);
    try std.testing.expect(attr.value == .i64);
    try std.testing.expectEqual(@as(i64, -100), attr.value.i64);
}

test "Attr.uint" {
    const attr = Attr.uint("size", 1024);
    try std.testing.expectEqualStrings("size", attr.key);
    try std.testing.expect(attr.value == .u64);
    try std.testing.expectEqual(@as(u64, 1024), attr.value.u64);
}

test "Attr.float" {
    const attr = Attr.float("ratio", 0.75);
    try std.testing.expectEqualStrings("ratio", attr.key);
    try std.testing.expect(attr.value == .f64);
    try std.testing.expectApproxEqRel(@as(f64, 0.75), attr.value.f64, 0.0001);
}

test "Attr.boolean" {
    const true_attr = Attr.boolean("enabled", true);
    const false_attr = Attr.boolean("disabled", false);

    try std.testing.expectEqualStrings("enabled", true_attr.key);
    try std.testing.expect(true_attr.value.bool == true);

    try std.testing.expectEqualStrings("disabled", false_attr.key);
    try std.testing.expect(false_attr.value.bool == false);
}

test "Attr.bytes" {
    const data = [_]u8{ 0x01, 0x02, 0x03 };
    const attr = Attr.bytes("data", &data);
    try std.testing.expectEqualStrings("data", attr.key);
    try std.testing.expect(attr.value == .bytes);
    try std.testing.expectEqualSlices(u8, &data, attr.value.bytes);
}

test "Attr.err" {
    const attr = Attr.err("error", error.FileNotFound);
    try std.testing.expectEqualStrings("error", attr.key);
    try std.testing.expect(attr.value == .err);
    try std.testing.expectEqual(error.FileNotFound, attr.value.err);
}

test "Attr.secret" {
    const attr = Attr.secret("password", "hunter2");
    try std.testing.expectEqualStrings("password", attr.key);
    try std.testing.expect(attr.value == .secret);
    try std.testing.expectEqualStrings("hunter2", attr.value.secret.value);
}

// ============================================================================
// Attr Array Tests
// ============================================================================

test "Attr array - multiple attrs" {
    const attrs = [_]Attr{
        Attr.string("name", "test"),
        Attr.int("count", 42),
        Attr.boolean("active", true),
    };

    try std.testing.expectEqual(@as(usize, 3), attrs.len);
    try std.testing.expectEqualStrings("name", attrs[0].key);
    try std.testing.expectEqualStrings("count", attrs[1].key);
    try std.testing.expectEqualStrings("active", attrs[2].key);
}

test "Attr array - empty" {
    const attrs: []const Attr = &.{};
    try std.testing.expectEqual(@as(usize, 0), attrs.len);
}

// ============================================================================
// Secret Tests
// ============================================================================

test "Secret - stores original value" {
    const s = Secret{ .value = "my-api-key" };
    try std.testing.expectEqualStrings("my-api-key", s.value);
}

test "Secret - different values" {
    const s1 = Secret{ .value = "key1" };
    const s2 = Secret{ .value = "key2" };
    try std.testing.expect(!std.mem.eql(u8, s1.value, s2.value));
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Value.str - empty string" {
    const v = Value{ .str = "" };
    try std.testing.expectEqualStrings("", v.str);
}

test "Value.bytes - empty" {
    const v = Value{ .bytes = &[_]u8{} };
    try std.testing.expectEqual(@as(usize, 0), v.bytes.len);
}

test "Attr - empty key" {
    const attr = Attr.string("", "value");
    try std.testing.expectEqualStrings("", attr.key);
}

test "Attr - unicode key" {
    const attr = Attr.string("日本語", "value");
    try std.testing.expectEqualStrings("日本語", attr.key);
}

test "Attr - unicode value" {
    const attr = Attr.string("greeting", "こんにちは");
    try std.testing.expectEqualStrings("こんにちは", attr.value.str);
}
