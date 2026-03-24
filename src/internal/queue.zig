// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Bounded queue for async log handling.
//!
//! Provides a thread-safe bounded queue with drop-oldest policy
//! for use by the AsyncHandler.
//!
//! ## Attribute serialization
//!
//! When a Record is copied into a QueuedRecord, all attribute values are
//! serialized to their string representation and stored in fixed-size
//! buffers. This means:
//!
//! - All deserialized attributes will have `.str` type values
//! - Numeric values are formatted as decimal strings
//! - Boolean values become "true" or "false"
//! - Secret values are redacted to "[REDACTED]" at serialization time
//! - Bytes are hex-encoded with "0x" prefix
//! - Error values use the error name string
//! - Marshaler values become "<marshaler>"
//!
//! This is a deliberate design choice: the queue owns all data by value,
//! requiring no heap allocation and no pointer lifetime management.

const std = @import("std");
const Record = @import("../record.zig").Record;
const Attr = @import("../value.zig").Attr;
const Value = @import("../value.zig").Value;
const redact = @import("../util/redact.zig");
const metrics = @import("../metrics/metrics.zig");

/// Maximum number of attributes stored per queued record.
/// Reduced from 32 to 8 -- most log records use fewer than 5 attributes.
/// With 8 attrs: QueuedRecord ~3KB vs ~12.5KB at 32.
pub const MAX_STORED_ATTRS = 8;

/// Maximum key length for a stored attribute.
const MAX_KEY_LEN = 64;

/// Maximum value length for a stored attribute.
/// Reduced from 256 to 128 -- covers most practical value lengths.
const MAX_VALUE_LEN = 128;

/// Queue errors.
pub const QueueError = error{
    QueueFull,
    QueueEmpty,
    Timeout,
};

/// An attribute with owned key and value data stored in fixed-size buffers.
/// All values are serialized to string representation at copy time.
pub const StoredAttr = struct {
    key_buf: [MAX_KEY_LEN]u8,
    key_len: usize,
    value_buf: [MAX_VALUE_LEN]u8,
    value_len: usize,

    pub fn key(self: *const StoredAttr) []const u8 {
        return self.key_buf[0..self.key_len];
    }

    pub fn value(self: *const StoredAttr) []const u8 {
        return self.value_buf[0..self.value_len];
    }

    /// Convert to an Attr with .str value pointing into this StoredAttr's buffers.
    pub fn toAttr(self: *const StoredAttr) Attr {
        return Attr.string(self.key(), self.value());
    }
};

/// Serialize a Value union to a string representation in the given buffer.
/// Returns the number of bytes written.
fn serializeValue(buf: *[MAX_VALUE_LEN]u8, val: Value) usize {
    switch (val) {
        .str => |s| {
            const copy_len = @min(s.len, buf.len);
            @memcpy(buf[0..copy_len], s[0..copy_len]);
            return copy_len;
        },
        .i64 => |i| {
            // Use std.fmt.printInt which writes the formatted integer into a buffer
            // and returns the number of characters written.
            if (i < 0) {
                buf[0] = '-';
                // Format the absolute value. For min i64, we handle it by
                // casting to u64 after negation in two's complement.
                const abs: u64 = if (i == std.math.minInt(i64))
                    @bitCast(-%(i))
                else
                    @intCast(-i);
                const len = std.fmt.printInt(buf[1..], abs, 10, .lower, .{});
                return len + 1;
            } else {
                const unsigned: u64 = @intCast(i);
                return std.fmt.printInt(buf, unsigned, 10, .lower, .{});
            }
        },
        .u64 => |u| {
            return std.fmt.printInt(buf, u, 10, .lower, .{});
        },
        .f64 => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                const null_str = "null";
                @memcpy(buf[0..null_str.len], null_str);
                return null_str.len;
            }
            var fbs = std.io.fixedBufferStream(buf);
            fbs.writer().print("{d:.6}", .{f}) catch {
                const fallback = "0.000000";
                @memcpy(buf[0..fallback.len], fallback);
                return fallback.len;
            };
            return fbs.pos;
        },
        .bool => |b| {
            const s = if (b) "true" else "false";
            @memcpy(buf[0..s.len], s);
            return s.len;
        },
        .secret => {
            @memcpy(buf[0..redact.REDACTED.len], redact.REDACTED);
            return redact.REDACTED.len;
        },
        .bytes => |b| {
            // Hex-encode with 0x prefix
            var pos: usize = 0;
            if (pos + 2 > buf.len) return 0;
            buf[0] = '0';
            buf[1] = 'x';
            pos = 2;
            for (b) |byte| {
                if (pos + 2 > buf.len) break;
                const hex = std.fmt.bytesToHex([1]u8{byte}, .lower);
                buf[pos] = hex[0];
                buf[pos + 1] = hex[1];
                pos += 2;
            }
            return pos;
        },
        .err => |e| {
            const raw: u16 = @intFromError(e);
            if (raw == 0) {
                const s = "error(0)";
                @memcpy(buf[0..s.len], s);
                return s.len;
            }
            const name = @errorName(e);
            const copy_len = @min(name.len, buf.len);
            @memcpy(buf[0..copy_len], name[0..copy_len]);
            return copy_len;
        },
        .marshaler => {
            const s = "<marshaler>";
            @memcpy(buf[0..s.len], s);
            return s.len;
        },
    }
}

/// A bounded record for the queue (owns copies of string data).
pub const QueuedRecord = struct {
    time_utc_us: i128,
    level_int: i32,
    msg_id_buf: [64]u8,
    msg_id_len: usize,
    message_buf: [1024]u8,
    message_len: usize,
    logger_buf: [128]u8,
    logger_len: usize,
    source_file_buf: [128]u8,
    source_file_len: usize,
    source_line: u32,
    /// Fixed-size storage for attributes. All values are serialized to strings.
    stored_attrs: [MAX_STORED_ATTRS]StoredAttr,
    attrs_count: usize,
    valid: bool,

    pub fn fromRecord(rec: *const Record) QueuedRecord {
        var qr = QueuedRecord{
            .time_utc_us = rec.time_utc_us,
            .level_int = @intFromEnum(rec.level),
            .msg_id_buf = undefined,
            .msg_id_len = @min(rec.msg_id.len, 64),
            .message_buf = undefined,
            .message_len = @min(rec.message.len, 1024),
            .logger_buf = undefined,
            .logger_len = @min(rec.logger.len, 128),
            .source_file_buf = undefined,
            .source_file_len = @min(rec.source_file.len, 128),
            .source_line = rec.source_line,
            .stored_attrs = undefined,
            .attrs_count = 0,
            .valid = true,
        };

        @memcpy(qr.msg_id_buf[0..qr.msg_id_len], rec.msg_id[0..qr.msg_id_len]);
        @memcpy(qr.message_buf[0..qr.message_len], rec.message[0..qr.message_len]);
        @memcpy(qr.logger_buf[0..qr.logger_len], rec.logger[0..qr.logger_len]);
        @memcpy(qr.source_file_buf[0..qr.source_file_len], rec.source_file[0..qr.source_file_len]);

        // Copy attributes with value serialization.
        // If the record has more attributes than MAX_STORED_ATTRS, the
        // excess are silently dropped and counted as dropped metrics.
        const count = @min(rec.attrs.len, MAX_STORED_ATTRS);
        if (rec.attrs.len > MAX_STORED_ATTRS) {
            metrics.global.incDropped(rec.attrs.len - MAX_STORED_ATTRS);
        }
        for (rec.attrs[0..count], 0..) |attr, idx| {
            var stored: StoredAttr = undefined;

            // Copy key
            const key_len = @min(attr.key.len, MAX_KEY_LEN);
            @memcpy(stored.key_buf[0..key_len], attr.key[0..key_len]);
            stored.key_len = key_len;

            // Serialize value to string
            stored.value_len = serializeValue(&stored.value_buf, attr.value);

            qr.stored_attrs[idx] = stored;
        }
        qr.attrs_count = count;

        return qr;
    }

    pub fn msgId(self: *const QueuedRecord) []const u8 {
        return self.msg_id_buf[0..self.msg_id_len];
    }

    pub fn message(self: *const QueuedRecord) []const u8 {
        return self.message_buf[0..self.message_len];
    }

    pub fn logger(self: *const QueuedRecord) []const u8 {
        return self.logger_buf[0..self.logger_len];
    }

    pub fn sourceFile(self: *const QueuedRecord) []const u8 {
        return self.source_file_buf[0..self.source_file_len];
    }

    /// Build an array of Attr structs from stored attributes.
    /// The returned slice points into the stored_attrs buffers of this QueuedRecord
    /// and is valid only while this QueuedRecord is alive.
    pub fn attrs(self: *const QueuedRecord, out: *[MAX_STORED_ATTRS]Attr) []const Attr {
        for (self.stored_attrs[0..self.attrs_count], 0..) |*sa, idx| {
            out[idx] = sa.toAttr();
        }
        return out[0..self.attrs_count];
    }
};

/// Thread-safe bounded queue with drop-oldest policy.
pub fn BoundedQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: []T,
        head: usize,
        tail: usize,
        count: usize,
        dropped: usize,
        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition,
        not_full: std.Thread.Condition,
        /// Condition variable signaled when the queue becomes empty.
        empty: std.Thread.Condition,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            const buffer = try allocator.alloc(T, capacity);
            return Self{
                .buffer = buffer,
                .head = 0,
                .tail = 0,
                .count = 0,
                .dropped = 0,
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .empty = .{},
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.buffer);
        }

        /// Push item, dropping oldest if full.
        /// Returns the queue length after the push, allowing callers to
        /// avoid a separate `len()` call (which would re-acquire the mutex).
        pub fn pushDropOldest(self: *Self, item: T) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == self.buffer.len) {
                // Drop oldest
                self.head = (self.head + 1) % self.buffer.len;
                self.count -= 1;
                self.dropped += 1;
            }

            self.buffer[self.tail] = item;
            self.tail = (self.tail + 1) % self.buffer.len;
            self.count += 1;
            self.not_empty.signal();
            return self.count;
        }

        /// Push item, blocking if full (with timeout).
        pub fn pushBlocking(self: *Self, item: T, timeout_ms: u32) QueueError!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == self.buffer.len) {
                if (timeout_ms == 0) {
                    return error.QueueFull;
                }
                // Wait for space
                const timeout_ns = @as(u64, timeout_ms) * std.time.ns_per_ms;
                self.not_full.timedWait(&self.mutex, timeout_ns) catch {
                    return error.Timeout;
                };
                if (self.count == self.buffer.len) {
                    return error.QueueFull;
                }
            }

            self.buffer[self.tail] = item;
            self.tail = (self.tail + 1) % self.buffer.len;
            self.count += 1;
            self.not_empty.signal();
        }

        /// Pop item, blocking until available.
        pub fn pop(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.count == 0) {
                self.not_empty.wait(&self.mutex);
            }

            const item = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.count -= 1;
            self.not_full.signal();
            if (self.count == 0) self.empty.broadcast();
            return item;
        }

        /// Try to pop item without blocking.
        pub fn tryPop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == 0) return null;

            const item = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.count -= 1;
            self.not_full.signal();
            if (self.count == 0) self.empty.broadcast();
            return item;
        }

        /// Pop with timeout.
        pub fn popTimeout(self: *Self, timeout_ms: u32) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == 0) {
                if (timeout_ms == 0) return null;
                const timeout_ns = @as(u64, timeout_ms) * std.time.ns_per_ms;
                self.not_empty.timedWait(&self.mutex, timeout_ns) catch return null;
                if (self.count == 0) return null;
            }

            const item = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.count -= 1;
            self.not_full.signal();
            if (self.count == 0) self.empty.broadcast();
            return item;
        }

        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.count;
        }

        pub fn droppedCount(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.dropped;
        }

        pub fn resetDropped(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            const d = self.dropped;
            self.dropped = 0;
            return d;
        }

        /// Wait until the queue is empty or the timeout expires.
        /// Returns true if the queue is empty, false on timeout.
        pub fn waitEmpty(self: *Self, timeout_ms: u32) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == 0) return true;
            if (timeout_ms == 0) return false;

            const timeout_ns = @as(u64, timeout_ms) * std.time.ns_per_ms;
            self.empty.timedWait(&self.mutex, timeout_ns) catch return self.count == 0;
            return self.count == 0;
        }
    };
}

test "BoundedQueue basic operations" {
    var queue = try BoundedQueue(u32).init(std.testing.allocator, 4);
    defer queue.deinit(std.testing.allocator);

    queue.pushDropOldest(1);
    queue.pushDropOldest(2);
    try std.testing.expectEqual(@as(usize, 2), queue.len());

    const v = queue.tryPop();
    try std.testing.expectEqual(@as(u32, 1), v.?);
}

test "BoundedQueue drop oldest" {
    var queue = try BoundedQueue(u32).init(std.testing.allocator, 2);
    defer queue.deinit(std.testing.allocator);

    queue.pushDropOldest(1);
    queue.pushDropOldest(2);
    queue.pushDropOldest(3); // Should drop 1

    try std.testing.expectEqual(@as(usize, 1), queue.droppedCount());
    try std.testing.expectEqual(@as(u32, 2), queue.tryPop().?);
    try std.testing.expectEqual(@as(u32, 3), queue.tryPop().?);
}

test "QueuedRecord fromRecord preserves string attrs" {
    const rec = Record{
        .time_utc_us = 1000000,
        .level = .info,
        .msg_id = "test.id",
        .message = "test message",
        .logger = "test.logger",
        .source_file = "test.zig",
        .source_line = 42,
        .attrs = &.{
            Attr.string("host", "localhost"),
            Attr.string("path", "/api/v1"),
        },
    };

    const qr = QueuedRecord.fromRecord(&rec);
    try std.testing.expect(qr.valid);
    try std.testing.expectEqualStrings("test.id", qr.msgId());
    try std.testing.expectEqualStrings("test message", qr.message());
    try std.testing.expectEqual(@as(usize, 2), qr.attrs_count);

    var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
    const stored_attrs = qr.attrs(&attr_buf);
    try std.testing.expectEqual(@as(usize, 2), stored_attrs.len);
    try std.testing.expectEqualStrings("host", stored_attrs[0].key);
    try std.testing.expectEqualStrings("localhost", stored_attrs[0].value.str);
    try std.testing.expectEqualStrings("path", stored_attrs[1].key);
    try std.testing.expectEqualStrings("/api/v1", stored_attrs[1].value.str);
}

test "QueuedRecord fromRecord serializes i64 values" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.int("count", 42),
            Attr.int("negative", -100),
            Attr.int("zero", 0),
        },
    };

    const qr = QueuedRecord.fromRecord(&rec);
    try std.testing.expectEqual(@as(usize, 3), qr.attrs_count);

    var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
    const stored_attrs = qr.attrs(&attr_buf);
    try std.testing.expectEqualStrings("count", stored_attrs[0].key);
    try std.testing.expectEqualStrings("42", stored_attrs[0].value.str);
    try std.testing.expectEqualStrings("negative", stored_attrs[1].key);
    try std.testing.expectEqualStrings("-100", stored_attrs[1].value.str);
    try std.testing.expectEqualStrings("zero", stored_attrs[2].key);
    try std.testing.expectEqualStrings("0", stored_attrs[2].value.str);
}

test "QueuedRecord fromRecord serializes u64 values" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.uint("requests", 1000),
        },
    };

    const qr = QueuedRecord.fromRecord(&rec);
    var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
    const stored_attrs = qr.attrs(&attr_buf);
    try std.testing.expectEqualStrings("requests", stored_attrs[0].key);
    try std.testing.expectEqualStrings("1000", stored_attrs[0].value.str);
}

test "QueuedRecord fromRecord serializes f64 values" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.float("ratio", 3.14),
        },
    };

    const qr = QueuedRecord.fromRecord(&rec);
    var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
    const stored_attrs = qr.attrs(&attr_buf);
    try std.testing.expectEqualStrings("ratio", stored_attrs[0].key);
    // f64 is formatted with 6 decimal places
    try std.testing.expect(std.mem.indexOf(u8, stored_attrs[0].value.str, "3.14") != null);
}

test "QueuedRecord fromRecord redacts secret values" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.secret("password", "super_secret_123"),
        },
    };

    const qr = QueuedRecord.fromRecord(&rec);
    var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
    const stored_attrs = qr.attrs(&attr_buf);
    try std.testing.expectEqual(@as(usize, 1), stored_attrs.len);
    try std.testing.expectEqualStrings("password", stored_attrs[0].key);
    try std.testing.expectEqualStrings("[REDACTED]", stored_attrs[0].value.str);
    // Verify the secret value is NOT present anywhere in the stored data
    const stored = &qr.stored_attrs[0];
    const value_data = stored.value_buf[0..stored.value_len];
    try std.testing.expect(std.mem.indexOf(u8, value_data, "super_secret") == null);
}

test "QueuedRecord fromRecord serializes bool values" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.boolean("enabled", true),
            Attr.boolean("debug", false),
        },
    };

    const qr = QueuedRecord.fromRecord(&rec);
    var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
    const stored_attrs = qr.attrs(&attr_buf);
    try std.testing.expectEqualStrings("true", stored_attrs[0].value.str);
    try std.testing.expectEqualStrings("false", stored_attrs[1].value.str);
}

test "QueuedRecord fromRecord serializes error values" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.err("cause", error.OutOfMemory),
        },
    };

    const qr = QueuedRecord.fromRecord(&rec);
    var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
    const stored_attrs = qr.attrs(&attr_buf);
    try std.testing.expectEqualStrings("cause", stored_attrs[0].key);
    try std.testing.expectEqualStrings("OutOfMemory", stored_attrs[0].value.str);
}

test "QueuedRecord fromRecord serializes bytes values" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.bytes("data", &[_]u8{ 0xde, 0xad, 0xbe, 0xef }),
        },
    };

    const qr = QueuedRecord.fromRecord(&rec);
    var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
    const stored_attrs = qr.attrs(&attr_buf);
    try std.testing.expectEqualStrings("data", stored_attrs[0].key);
    try std.testing.expectEqualStrings("0xdeadbeef", stored_attrs[0].value.str);
}

test "QueuedRecord fromRecord handles mixed attr types" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("host", "localhost"),
            Attr.int("port", 8080),
            Attr.boolean("tls", true),
            Attr.secret("token", "abc123"),
        },
    };

    const qr = QueuedRecord.fromRecord(&rec);
    try std.testing.expectEqual(@as(usize, 4), qr.attrs_count);

    var attr_buf: [MAX_STORED_ATTRS]Attr = undefined;
    const stored_attrs = qr.attrs(&attr_buf);
    try std.testing.expectEqualStrings("localhost", stored_attrs[0].value.str);
    try std.testing.expectEqualStrings("8080", stored_attrs[1].value.str);
    try std.testing.expectEqualStrings("true", stored_attrs[2].value.str);
    try std.testing.expectEqualStrings("[REDACTED]", stored_attrs[3].value.str);
}

test "serializeValue handles NaN and Inf" {
    var buf: [MAX_VALUE_LEN]u8 = undefined;

    const nan_len = serializeValue(&buf, Value{ .f64 = std.math.nan(f64) });
    try std.testing.expectEqualStrings("null", buf[0..nan_len]);

    const inf_len = serializeValue(&buf, Value{ .f64 = std.math.inf(f64) });
    try std.testing.expectEqualStrings("null", buf[0..inf_len]);
}

test "BoundedQueue waitEmpty" {
    var queue = try BoundedQueue(u32).init(std.testing.allocator, 4);
    defer queue.deinit(std.testing.allocator);

    // Empty queue should return true immediately
    try std.testing.expect(queue.waitEmpty(0));

    queue.pushDropOldest(1);

    // Non-empty queue with zero timeout should return false
    try std.testing.expect(!queue.waitEmpty(0));

    // Pop the item
    _ = queue.tryPop();

    // Now empty again
    try std.testing.expect(queue.waitEmpty(0));
}
