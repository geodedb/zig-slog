// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Logger - the main interface for structured logging.
//!
//! Logger wraps a handler and provides a convenient API for logging
//! at various levels with structured attributes.

const std = @import("std");
const Level = @import("level.zig").Level;
const Attr = @import("value.zig").Attr;
const Record = @import("record.zig").Record;
const RecordError = @import("record.zig").RecordError;
const Handler = @import("handler.zig").Handler;
const HandlerError = @import("handler.zig").HandlerError;
const Clock = @import("internal/clock.zig").Clock;
const Translator = @import("i18n/catalog.zig").Translator;
const metrics = @import("metrics/metrics.zig");

/// Default fatal hook that panics.
fn defaultFatalHook(_: *const Record) void {
    @panic("fatal log message");
}

/// Fatal hook called after logging a fatal message.
pub var fatal_hook: *const fn (*const Record) void = defaultFatalHook;

/// Logger provides the main logging interface.
pub const Logger = struct {
    handler: Handler,
    level: Level,
    clock: Clock,
    name: []const u8,
    context_attrs: []const Attr,
    translator: ?Translator,
    locale: []const u8,

    /// Initialize a new logger.
    pub fn init(handler: Handler, level: Level, clock: Clock) Logger {
        return .{
            .handler = handler,
            .level = level,
            .clock = clock,
            .name = "",
            .context_attrs = &.{},
            .translator = null,
            .locale = "en",
        };
    }

    /// Create a named child logger.
    pub fn named(self: Logger, child_name: []const u8) Logger {
        // In a real impl, we'd concatenate parent.child
        return .{
            .handler = self.handler,
            .level = self.level,
            .clock = self.clock,
            .name = child_name,
            .context_attrs = self.context_attrs,
            .translator = self.translator,
            .locale = self.locale,
        };
    }

    /// Create a logger with additional context attributes.
    pub fn with(self: Logger, attrs: []const Attr) Logger {
        return .{
            .handler = self.handler.withAttrs(attrs),
            .level = self.level,
            .clock = self.clock,
            .name = self.name,
            .context_attrs = attrs,
            .translator = self.translator,
            .locale = self.locale,
        };
    }

    /// Create a logger with a group prefix for attribute keys.
    pub fn withGroup(self: Logger, prefix: []const u8) Logger {
        return .{
            .handler = self.handler.withGroup(prefix),
            .level = self.level,
            .clock = self.clock,
            .name = self.name,
            .context_attrs = self.context_attrs,
            .translator = self.translator,
            .locale = self.locale,
        };
    }

    /// Create a logger with translation support.
    pub fn withTranslator(self: Logger, locale: []const u8, t: Translator) Logger {
        return .{
            .handler = self.handler,
            .level = self.level,
            .clock = self.clock,
            .name = self.name,
            .context_attrs = self.context_attrs,
            .translator = t,
            .locale = locale,
        };
    }

    /// Set the minimum log level.
    pub fn setLevel(self: *Logger, level: Level) void {
        self.level = level;
        self.handler.setLevel(level);
    }

    /// Check if the given level is enabled.
    pub fn enabled(self: *const Logger, level: Level) bool {
        return level.atLeast(self.level);
    }

    /// Log at the specified level.
    pub fn log(
        self: *const Logger,
        level: Level,
        msg_id: []const u8,
        attrs: []const Attr,
    ) (HandlerError || RecordError)!void {
        if (!self.enabled(level)) return;

        // Translate message if translator is available
        const message = if (self.translator) |t|
            t.translate(self.locale, msg_id) orelse msg_id
        else
            msg_id;

        const rec = Record{
            .time_utc_us = self.clock.now(),
            .level = level,
            .msg_id = msg_id,
            .message = message,
            .logger = self.name,
            .source_file = "",
            .source_line = 0,
            .attrs = attrs,
        };

        // Check limits
        if (rec.hasTooManyAttrs()) return error.TooManyAttrs;
        if (rec.isTooLarge()) return error.RecordTooLarge;

        try self.handler.handle(&rec);
        metrics.global.incEmitted();

        if (level == .fatal) {
            fatal_hook(&rec);
        }
    }

    /// Log at the specified level with source location.
    pub fn logSrc(
        self: *const Logger,
        level: Level,
        msg_id: []const u8,
        attrs: []const Attr,
        src: std.builtin.SourceLocation,
    ) (HandlerError || RecordError)!void {
        if (!self.enabled(level)) return;

        const message = if (self.translator) |t|
            t.translate(self.locale, msg_id) orelse msg_id
        else
            msg_id;

        const rec = Record{
            .time_utc_us = self.clock.now(),
            .level = level,
            .msg_id = msg_id,
            .message = message,
            .logger = self.name,
            .source_file = src.file,
            .source_line = src.line,
            .attrs = attrs,
        };

        if (rec.hasTooManyAttrs()) return error.TooManyAttrs;
        if (rec.isTooLarge()) return error.RecordTooLarge;

        try self.handler.handle(&rec);
        metrics.global.incEmitted();

        if (level == .fatal) {
            fatal_hook(&rec);
        }
    }

    /// Log a trace message.
    pub fn trace(self: *const Logger, msg_id: []const u8, attrs: []const Attr) !void {
        try self.log(.trace, msg_id, attrs);
    }

    /// Log a debug message.
    pub fn debug(self: *const Logger, msg_id: []const u8, attrs: []const Attr) !void {
        try self.log(.debug, msg_id, attrs);
    }

    /// Log an info message.
    pub fn info(self: *const Logger, msg_id: []const u8, attrs: []const Attr) !void {
        try self.log(.info, msg_id, attrs);
    }

    /// Log a warning message.
    pub fn warn(self: *const Logger, msg_id: []const u8, attrs: []const Attr) !void {
        try self.log(.warn, msg_id, attrs);
    }

    /// Log an error message.
    pub fn @"error"(self: *const Logger, msg_id: []const u8, attrs: []const Attr) !void {
        try self.log(.@"error", msg_id, attrs);
    }

    /// Log a fatal message (will call fatal_hook after logging).
    pub fn fatal(self: *const Logger, msg_id: []const u8, attrs: []const Attr) !void {
        try self.log(.fatal, msg_id, attrs);
    }

    /// Flush the handler with timeout.
    pub fn flush(self: *const Logger, timeout_ms: u32) !void {
        try self.handler.flush(timeout_ms);
    }
};

test "Logger.enabled" {
    const handler = @import("handlers/discard_handler.zig").init();
    const logger = Logger.init(handler, .info, Clock.system());

    try std.testing.expect(!logger.enabled(.debug));
    try std.testing.expect(logger.enabled(.info));
    try std.testing.expect(logger.enabled(.@"error"));
}

test "Logger.named" {
    const handler = @import("handlers/discard_handler.zig").init();
    const logger = Logger.init(handler, .info, Clock.system());
    const child = logger.named("child");

    try std.testing.expectEqualStrings("child", child.name);
}
