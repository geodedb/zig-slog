// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Log record containing all information about a single log event.

const std = @import("std");
const Level = @import("level.zig").Level;
const Attr = @import("value.zig").Attr;

/// Maximum number of attributes per record.
pub const MAX_ATTRS = 64;

/// Maximum record size in bytes.
pub const MAX_RECORD_SIZE = 64 * 1024;

/// A log record containing all information about a single log event.
pub const Record = struct {
    /// Timestamp in microseconds since Unix epoch (UTC).
    time_utc_us: i128,
    /// Log level.
    level: Level,
    /// Message identifier (for i18n lookup).
    msg_id: []const u8,
    /// Formatted message (after translation if applicable).
    message: []const u8,
    /// Logger name (hierarchical, dot-separated).
    logger: []const u8,
    /// Source file where the log was emitted.
    source_file: []const u8,
    /// Source line number.
    source_line: u32,
    /// Structured attributes.
    attrs: []const Attr,

    /// Estimates the serialized size of this record.
    pub fn estimatedSize(self: *const Record) usize {
        var size: usize = 128; // base overhead
        size += self.msg_id.len;
        size += self.message.len;
        size += self.logger.len;
        size += self.source_file.len;

        for (self.attrs) |attr| {
            size += attr.key.len + attr.value.estimatedSize() + 8;
        }

        return size;
    }

    /// Returns true if the record is too large.
    pub fn isTooLarge(self: *const Record) bool {
        return self.estimatedSize() > MAX_RECORD_SIZE;
    }

    /// Returns true if the record has too many attributes.
    pub fn hasTooManyAttrs(self: *const Record) bool {
        return self.attrs.len > MAX_ATTRS;
    }
};

/// Errors that can occur when processing records.
pub const RecordError = error{
    RecordTooLarge,
    TooManyAttrs,
    InvalidNumber,
    InvalidUtf8,
    OutputFull,
};

test "Record.estimatedSize" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test message",
        .logger = "test.logger",
        .source_file = "test.zig",
        .source_line = 42,
        .attrs = &.{},
    };
    try std.testing.expect(rec.estimatedSize() > 0);
    try std.testing.expect(!rec.isTooLarge());
}
