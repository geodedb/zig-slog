// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Bounded queue for async log handling.
//!
//! Provides a thread-safe bounded queue with drop-oldest policy
//! for use by the AsyncHandler.

const std = @import("std");
const Record = @import("../record.zig").Record;

/// Queue errors.
pub const QueueError = error{
    QueueFull,
    QueueEmpty,
    Timeout,
};

/// A bounded record for the queue (owns copies of string data).
pub const QueuedRecord = struct {
    time_utc_us: i128,
    level_int: i32,
    msg_id_buf: [256]u8,
    msg_id_len: usize,
    message_buf: [1024]u8,
    message_len: usize,
    logger_buf: [128]u8,
    logger_len: usize,
    source_file_buf: [256]u8,
    source_file_len: usize,
    source_line: u32,
    // Simplified: attrs stored as serialized key=value pairs
    attrs_buf: [2048]u8,
    attrs_len: usize,
    valid: bool,

    pub fn fromRecord(rec: *const Record) QueuedRecord {
        var qr = QueuedRecord{
            .time_utc_us = rec.time_utc_us,
            .level_int = @intFromEnum(rec.level),
            .msg_id_buf = undefined,
            .msg_id_len = @min(rec.msg_id.len, 256),
            .message_buf = undefined,
            .message_len = @min(rec.message.len, 1024),
            .logger_buf = undefined,
            .logger_len = @min(rec.logger.len, 128),
            .source_file_buf = undefined,
            .source_file_len = @min(rec.source_file.len, 256),
            .source_line = rec.source_line,
            .attrs_buf = undefined,
            .attrs_len = 0,
            .valid = true,
        };

        @memcpy(qr.msg_id_buf[0..qr.msg_id_len], rec.msg_id[0..qr.msg_id_len]);
        @memcpy(qr.message_buf[0..qr.message_len], rec.message[0..qr.message_len]);
        @memcpy(qr.logger_buf[0..qr.logger_len], rec.logger[0..qr.logger_len]);
        @memcpy(qr.source_file_buf[0..qr.source_file_len], rec.source_file[0..qr.source_file_len]);

        // Serialize attrs into buffer
        var pos: usize = 0;
        for (rec.attrs) |attr| {
            const key = attr.key;
            if (pos + key.len + 16 > qr.attrs_buf.len) break;

            @memcpy(qr.attrs_buf[pos..][0..key.len], key);
            pos += key.len;
            qr.attrs_buf[pos] = '=';
            pos += 1;

            // Simple value serialization
            const value_str = switch (attr.value) {
                .str => |s| s,
                .i64 => |i| blk: {
                    var buf: [24]u8 = undefined;
                    const len = std.fmt.formatInt(i, 10, .lower, .{}, &buf) catch 0;
                    _ = len;
                    break :blk "";
                },
                else => "",
            };
            const value_len = @min(value_str.len, qr.attrs_buf.len - pos - 1);
            @memcpy(qr.attrs_buf[pos..][0..value_len], value_str[0..value_len]);
            pos += value_len;
            qr.attrs_buf[pos] = ';';
            pos += 1;
        }
        qr.attrs_len = pos;

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
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.buffer);
        }

        /// Push item, dropping oldest if full.
        pub fn pushDropOldest(self: *Self, item: T) void {
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
