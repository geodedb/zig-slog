// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Handler interface for processing log records.
//!
//! Handlers are responsible for formatting and outputting log records
//! to various destinations (console, files, network, etc.).

const std = @import("std");
const Level = @import("level.zig").Level;
const Attr = @import("value.zig").Attr;
const Record = @import("record.zig").Record;

/// Handler errors.
pub const HandlerError = error{
    WriteFailed,
    FlushFailed,
    ConnectionFailed,
    Timeout,
    BufferFull,
    InvalidRecord,
    FeatureDisabled,
    OutOfMemory,
};

/// Virtual table for handler operations.
pub const HandlerVTable = struct {
    /// Process a log record.
    handle: *const fn (ctx: *anyopaque, rec: *const Record) HandlerError!void,
    /// Create a new handler with additional attributes.
    withAttrs: *const fn (ctx: *anyopaque, addl: []const Attr) Handler,
    /// Create a new handler with a group prefix.
    withGroup: *const fn (ctx: *anyopaque, prefix: []const u8) Handler,
    /// Set the minimum log level.
    setLevel: *const fn (ctx: *anyopaque, level: Level) void,
    /// Flush pending records with timeout.
    flush: *const fn (ctx: *anyopaque, timeout_ms: u32) HandlerError!void,
    /// Optional: get current level.
    getLevel: ?*const fn (ctx: *anyopaque) Level = null,
    /// Optional: close/cleanup handler.
    close: ?*const fn (ctx: *anyopaque) void = null,
};

/// A handler processes log records and outputs them to a destination.
pub const Handler = struct {
    ctx: *anyopaque,
    vtable: *const HandlerVTable,

    /// Process a log record.
    pub fn handle(self: Handler, rec: *const Record) HandlerError!void {
        return self.vtable.handle(self.ctx, rec);
    }

    /// Create a new handler with additional context attributes.
    pub fn withAttrs(self: Handler, addl: []const Attr) Handler {
        return self.vtable.withAttrs(self.ctx, addl);
    }

    /// Create a new handler with a group prefix for attribute keys.
    pub fn withGroup(self: Handler, prefix: []const u8) Handler {
        return self.vtable.withGroup(self.ctx, prefix);
    }

    /// Set the minimum log level.
    pub fn setLevel(self: Handler, level: Level) void {
        self.vtable.setLevel(self.ctx, level);
    }

    /// Flush pending records to the destination.
    pub fn flush(self: Handler, timeout_ms: u32) HandlerError!void {
        return self.vtable.flush(self.ctx, timeout_ms);
    }

    /// Get the current minimum level (if supported).
    pub fn getLevel(self: Handler) ?Level {
        if (self.vtable.getLevel) |getLevelFn| {
            return getLevelFn(self.ctx);
        }
        return null;
    }

    /// Close the handler and release resources.
    pub fn close(self: Handler) void {
        if (self.vtable.close) |closeFn| {
            closeFn(self.ctx);
        }
    }
};

test "Handler vtable" {
    // Basic structure test
    const vtable = HandlerVTable{
        .handle = undefined,
        .withAttrs = undefined,
        .withGroup = undefined,
        .setLevel = undefined,
        .flush = undefined,
    };
    _ = vtable;
}
