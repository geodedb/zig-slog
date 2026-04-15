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
const MAX_ATTRS = @import("record.zig").MAX_ATTRS;
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
/// Access this field only via `getFatalHook` and `setFatalHook` to ensure
/// atomic ordering and avoid data races when the hook is changed
/// concurrently with logging.
var fatal_hook: *const fn (*const Record) void = defaultFatalHook;

const FatalHookFn = *const fn (*const Record) void;

/// Atomically load the current fatal hook.
pub fn getFatalHook() FatalHookFn {
    return @atomicLoad(FatalHookFn, &fatal_hook, .acquire);
}

/// Atomically store a new fatal hook.
pub fn setFatalHook(hook: FatalHookFn) void {
    @atomicStore(FatalHookFn, &fatal_hook, hook, .release);
}

/// Maximum length for a logger name (including parent.child concatenation).
const max_name_len = 256;

/// Logger provides the main logging interface.
pub const Logger = struct {
    handler: Handler,
    level: Level,
    clock: Clock,
    name: []const u8,
    name_buf: [max_name_len]u8 = .{0} ** max_name_len,
    name_len: u16 = 0,
    context_attrs: []const Attr,
    translator: ?Translator,
    locale: []const u8,

    /// Return the logger name. When the name is stored in the internal
    /// buffer (after concatenation), this returns a slice into the
    /// caller's own `name_buf`, which is safe because Logger is a
    /// value type and the buffer travels with the struct.
    pub fn getName(self: *const Logger) []const u8 {
        if (self.name_len > 0) {
            return self.name_buf[0..self.name_len];
        }
        return self.name;
    }

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
    /// If the current logger has a name, the child name is concatenated
    /// as "parent.child". If the current logger has no name, the child
    /// name is used as-is.
    pub fn named(self: Logger, child_name: []const u8) Logger {
        var child = Logger{
            .handler = self.handler,
            .level = self.level,
            .clock = self.clock,
            .name = child_name,
            .name_len = 0,
            .context_attrs = self.context_attrs,
            .translator = self.translator,
            .locale = self.locale,
        };

        const parent_name = self.getName();
        if (parent_name.len > 0) {
            // Copy the parent name into a temporary buffer to avoid
            // aliasing when self.name points into self.name_buf.
            var parent_tmp: [max_name_len]u8 = undefined;
            @memcpy(parent_tmp[0..parent_name.len], parent_name);
            const safe_parent = parent_tmp[0..parent_name.len];

            const written = std.fmt.bufPrint(&child.name_buf, "{s}.{s}", .{ safe_parent, child_name }) catch {
                // If the concatenated name exceeds the buffer, fall back to
                // using the child name alone.
                return child;
            };
            child.name_len = @intCast(written.len);
            child.name = "";
        }

        return child;
    }

    /// Create a logger with additional context attributes.
    pub fn with(self: Logger, attrs: []const Attr) Logger {
        return .{
            .handler = self.handler.withAttrs(attrs),
            .level = self.level,
            .clock = self.clock,
            .name = self.name,
            .name_buf = self.name_buf,
            .name_len = self.name_len,
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
            .name_buf = self.name_buf,
            .name_len = self.name_len,
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
            .name_buf = self.name_buf,
            .name_len = self.name_len,
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

        // Merge context_attrs with record attrs if context_attrs are present
        var combined_buf: [MAX_ATTRS]Attr = undefined;
        const effective_attrs = if (self.context_attrs.len > 0) blk: {
            const total = self.context_attrs.len + attrs.len;
            if (total > MAX_ATTRS) break :blk attrs; // fallback: too many
            @memcpy(combined_buf[0..self.context_attrs.len], self.context_attrs);
            @memcpy(combined_buf[self.context_attrs.len..][0..attrs.len], attrs);
            break :blk combined_buf[0..total];
        } else attrs;

        const rec = Record{
            .time_utc_us = self.clock.now(),
            .level = level,
            .msg_id = msg_id,
            .message = message,
            .logger = self.getName(),
            .source_file = "",
            .source_line = 0,
            .attrs = effective_attrs,
        };

        // Check limits
        if (rec.hasTooManyAttrs()) return error.TooManyAttrs;
        if (rec.isTooLarge()) return error.RecordTooLarge;

        try self.handler.handle(&rec);
        metrics.global.incEmitted();

        if (level == .fatal) {
            getFatalHook()(&rec);
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

        // Merge context_attrs with record attrs if context_attrs are present
        var combined_buf: [MAX_ATTRS]Attr = undefined;
        const effective_attrs = if (self.context_attrs.len > 0) blk: {
            const total = self.context_attrs.len + attrs.len;
            if (total > MAX_ATTRS) break :blk attrs; // fallback: too many
            @memcpy(combined_buf[0..self.context_attrs.len], self.context_attrs);
            @memcpy(combined_buf[self.context_attrs.len..][0..attrs.len], attrs);
            break :blk combined_buf[0..total];
        } else attrs;

        const rec = Record{
            .time_utc_us = self.clock.now(),
            .level = level,
            .msg_id = msg_id,
            .message = message,
            .logger = self.getName(),
            .source_file = src.file,
            .source_line = src.line,
            .attrs = effective_attrs,
        };

        if (rec.hasTooManyAttrs()) return error.TooManyAttrs;
        if (rec.isTooLarge()) return error.RecordTooLarge;

        try self.handler.handle(&rec);
        metrics.global.incEmitted();

        if (level == .fatal) {
            getFatalHook()(&rec);
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

test "Logger.named concatenates parent.child" {
    const handler = @import("handlers/discard_handler.zig").init();
    var logger = Logger.init(handler, .info, Clock.system());

    // When parent has no name, child name is used as-is
    const child = logger.named("child");
    try std.testing.expectEqualStrings("child", child.getName());

    // When parent has a name, result is "parent.child"
    logger.name = "parent";
    const child2 = logger.named("child");
    try std.testing.expectEqualStrings("parent.child", child2.getName());
}

test "Logger.named chained concatenation" {
    const handler = @import("handlers/discard_handler.zig").init();
    const logger = Logger.init(handler, .info, Clock.system());

    const http_logger = logger.named("http");
    try std.testing.expectEqualStrings("http", http_logger.getName());

    const server_logger = http_logger.named("server");
    try std.testing.expectEqualStrings("http.server", server_logger.getName());

    const handler_logger = server_logger.named("handler");
    try std.testing.expectEqualStrings("http.server.handler", handler_logger.getName());
}

test "Logger.named with empty parent uses child name" {
    const handler = @import("handlers/discard_handler.zig").init();
    const logger = Logger.init(handler, .info, Clock.system());

    try std.testing.expectEqualStrings("", logger.getName());

    const child = logger.named("myservice");
    try std.testing.expectEqualStrings("myservice", child.getName());
}

test "fatal_hook uses atomic access" {
    // Verify we can atomically load and store the fatal hook.
    const original = getFatalHook();

    const test_hook = struct {
        fn hook(_: *const Record) void {
            // no-op test hook (avoids panic)
        }
    }.hook;

    setFatalHook(test_hook);
    const loaded = getFatalHook();
    try std.testing.expect(loaded == test_hook);

    // Exercise the hook through Logger.fatal by swapping in a hook that
    // sets a flag instead of panicking.
    const flag_hook = struct {
        var called: bool = false;
        fn hook(_: *const Record) void {
            called = true;
        }
    };
    setFatalHook(flag_hook.hook);

    const discard_handler = @import("handlers/discard_handler.zig").init();
    const logger = Logger.init(discard_handler, .fatal, Clock.system());
    try logger.fatal("test.fatal", &.{});

    try std.testing.expect(flag_hook.called);

    // Restore original hook.
    setFatalHook(original);
}

test "Logger.with context attrs appear in output" {
    const text_handler = @import("handlers/text_handler.zig");
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = text_handler.Context.init(&fbs, .info, Clock.system());
    const handler = text_handler.init(&ctx);

    const base_logger = Logger.init(handler, .info, Clock.system());

    // Create a child logger with context attrs
    const child_logger = base_logger.with(&.{
        Attr.string("service", "auth"),
        Attr.int("version", 2),
    });

    // Log a message with per-record attrs
    try child_logger.info("request.handled", &.{
        Attr.int("status", 200),
    });

    const output = fbs.buffered();

    // Context attrs should appear in output
    try std.testing.expect(std.mem.indexOf(u8, output, "service=auth") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "version=2") != null);
    // Per-record attrs should also appear
    try std.testing.expect(std.mem.indexOf(u8, output, "status=200") != null);
    // Context attrs should come before record attrs
    const service_pos = std.mem.indexOf(u8, output, "service=auth").?;
    const status_pos = std.mem.indexOf(u8, output, "status=200").?;
    try std.testing.expect(service_pos < status_pos);
}

test "Logger.with context attrs appear in JSON output" {
    const json_handler = @import("handlers/json_handler.zig");
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = json_handler.Context.init(&fbs, .info, Clock.system());
    const handler = json_handler.init(&ctx);

    const base_logger = Logger.init(handler, .info, Clock.system());
    const child_logger = base_logger.with(&.{
        Attr.string("env", "prod"),
    });

    try child_logger.info("deploy.started", &.{
        Attr.string("app", "web"),
    });

    const output = fbs.buffered();

    // Context attr should appear in JSON output
    try std.testing.expect(std.mem.indexOf(u8, output, "\"env\":\"prod\"") != null);
    // Per-record attr should also appear
    try std.testing.expect(std.mem.indexOf(u8, output, "\"app\":\"web\"") != null);
}
