// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Log levels for slogz.
//!
//! Levels are ordered from most verbose (trace) to most severe (fatal).
//! The numeric values allow for custom intermediate levels if needed.

const std = @import("std");

/// Log level indicating the severity of a log message.
pub const Level = enum(i32) {
    /// Extremely detailed tracing information.
    trace = -8,
    /// Debugging information for development.
    debug = -4,
    /// General informational messages.
    info = 0,
    /// Warning messages indicating potential issues.
    warn = 4,
    /// Error messages indicating failures.
    @"error" = 8,
    /// Fatal errors that may terminate the program.
    fatal = 12,

    /// Returns the string representation of the level.
    pub fn asText(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .@"error" => "ERROR",
            .fatal => "FATAL",
        };
    }

    /// Returns the lowercase string representation.
    pub fn asLowerText(self: Level) []const u8 {
        return switch (self) {
            .trace => "trace",
            .debug => "debug",
            .info => "info",
            .warn => "warn",
            .@"error" => "error",
            .fatal => "fatal",
        };
    }

    /// Maps level to syslog severity (RFC5424).
    pub fn toSyslogSeverity(self: Level) u3 {
        return switch (self) {
            .trace, .debug => 7, // Debug
            .info => 6, // Informational
            .warn => 4, // Warning
            .@"error" => 3, // Error
            .fatal => 2, // Critical
        };
    }

    /// Parses a level from string (case-insensitive).
    pub fn parse(s: []const u8) ?Level {
        return fromString(s);
    }

    /// Parses a level from string (case-insensitive).
    pub fn fromString(s: []const u8) ?Level {
        const lower = blk: {
            var buf: [8]u8 = undefined;
            if (s.len > buf.len) return null;
            for (s, 0..) |c, i| {
                buf[i] = std.ascii.toLower(c);
            }
            break :blk buf[0..s.len];
        };

        if (std.mem.eql(u8, lower, "trace")) return .trace;
        if (std.mem.eql(u8, lower, "debug")) return .debug;
        if (std.mem.eql(u8, lower, "info")) return .info;
        if (std.mem.eql(u8, lower, "warn")) return .warn;
        if (std.mem.eql(u8, lower, "warning")) return .warn;
        if (std.mem.eql(u8, lower, "error")) return .@"error";
        if (std.mem.eql(u8, lower, "fatal")) return .fatal;
        return null;
    }

    /// Returns true if this level is at least as severe as the threshold.
    pub fn atLeast(self: Level, threshold: Level) bool {
        return @intFromEnum(self) >= @intFromEnum(threshold);
    }
};

test "Level.asText" {
    try std.testing.expectEqualStrings("INFO", Level.info.asText());
    try std.testing.expectEqualStrings("ERROR", Level.@"error".asText());
}

test "Level.fromString" {
    try std.testing.expectEqual(Level.info, Level.fromString("INFO").?);
    try std.testing.expectEqual(Level.info, Level.fromString("info").?);
    try std.testing.expectEqual(Level.warn, Level.fromString("warning").?);
    try std.testing.expect(Level.fromString("invalid") == null);
}

test "Level.atLeast" {
    try std.testing.expect(Level.@"error".atLeast(.info));
    try std.testing.expect(Level.info.atLeast(.info));
    try std.testing.expect(!Level.debug.atLeast(.info));
}
