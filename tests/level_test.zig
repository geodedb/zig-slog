//! Comprehensive unit tests for Level module.

const std = @import("std");
const Level = @import("slogz").Level;

// ============================================================================
// Level Value Tests
// ============================================================================

test "Level enum values" {
    try std.testing.expectEqual(@as(i32, -8), @intFromEnum(Level.trace));
    try std.testing.expectEqual(@as(i32, -4), @intFromEnum(Level.debug));
    try std.testing.expectEqual(@as(i32, 0), @intFromEnum(Level.info));
    try std.testing.expectEqual(@as(i32, 4), @intFromEnum(Level.warn));
    try std.testing.expectEqual(@as(i32, 8), @intFromEnum(Level.@"error"));
    try std.testing.expectEqual(@as(i32, 12), @intFromEnum(Level.fatal));
}

// ============================================================================
// Level Ordering Tests
// ============================================================================

test "Level.atLeast - trace" {
    try std.testing.expect(Level.trace.atLeast(.trace));
    try std.testing.expect(!Level.trace.atLeast(.debug));
    try std.testing.expect(!Level.trace.atLeast(.info));
    try std.testing.expect(!Level.trace.atLeast(.warn));
    try std.testing.expect(!Level.trace.atLeast(.@"error"));
    try std.testing.expect(!Level.trace.atLeast(.fatal));
}

test "Level.atLeast - debug" {
    try std.testing.expect(Level.debug.atLeast(.trace));
    try std.testing.expect(Level.debug.atLeast(.debug));
    try std.testing.expect(!Level.debug.atLeast(.info));
    try std.testing.expect(!Level.debug.atLeast(.warn));
    try std.testing.expect(!Level.debug.atLeast(.@"error"));
    try std.testing.expect(!Level.debug.atLeast(.fatal));
}

test "Level.atLeast - info" {
    try std.testing.expect(Level.info.atLeast(.trace));
    try std.testing.expect(Level.info.atLeast(.debug));
    try std.testing.expect(Level.info.atLeast(.info));
    try std.testing.expect(!Level.info.atLeast(.warn));
    try std.testing.expect(!Level.info.atLeast(.@"error"));
    try std.testing.expect(!Level.info.atLeast(.fatal));
}

test "Level.atLeast - warn" {
    try std.testing.expect(Level.warn.atLeast(.trace));
    try std.testing.expect(Level.warn.atLeast(.debug));
    try std.testing.expect(Level.warn.atLeast(.info));
    try std.testing.expect(Level.warn.atLeast(.warn));
    try std.testing.expect(!Level.warn.atLeast(.@"error"));
    try std.testing.expect(!Level.warn.atLeast(.fatal));
}

test "Level.atLeast - error" {
    try std.testing.expect(Level.@"error".atLeast(.trace));
    try std.testing.expect(Level.@"error".atLeast(.debug));
    try std.testing.expect(Level.@"error".atLeast(.info));
    try std.testing.expect(Level.@"error".atLeast(.warn));
    try std.testing.expect(Level.@"error".atLeast(.@"error"));
    try std.testing.expect(!Level.@"error".atLeast(.fatal));
}

test "Level.atLeast - fatal" {
    try std.testing.expect(Level.fatal.atLeast(.trace));
    try std.testing.expect(Level.fatal.atLeast(.debug));
    try std.testing.expect(Level.fatal.atLeast(.info));
    try std.testing.expect(Level.fatal.atLeast(.warn));
    try std.testing.expect(Level.fatal.atLeast(.@"error"));
    try std.testing.expect(Level.fatal.atLeast(.fatal));
}

// ============================================================================
// Level Text Representation Tests
// ============================================================================

test "Level.asText" {
    try std.testing.expectEqualStrings("TRACE", Level.trace.asText());
    try std.testing.expectEqualStrings("DEBUG", Level.debug.asText());
    try std.testing.expectEqualStrings("INFO", Level.info.asText());
    try std.testing.expectEqualStrings("WARN", Level.warn.asText());
    try std.testing.expectEqualStrings("ERROR", Level.@"error".asText());
    try std.testing.expectEqualStrings("FATAL", Level.fatal.asText());
}

// ============================================================================
// Level Syslog Severity Mapping Tests
// ============================================================================

test "Level.toSyslogSeverity" {
    // Syslog severity: 7=debug, 6=info, 4=warning, 3=error, 2=critical
    try std.testing.expectEqual(@as(u3, 7), Level.trace.toSyslogSeverity());
    try std.testing.expectEqual(@as(u3, 7), Level.debug.toSyslogSeverity());
    try std.testing.expectEqual(@as(u3, 6), Level.info.toSyslogSeverity());
    try std.testing.expectEqual(@as(u3, 4), Level.warn.toSyslogSeverity());
    try std.testing.expectEqual(@as(u3, 3), Level.@"error".toSyslogSeverity());
    try std.testing.expectEqual(@as(u3, 2), Level.fatal.toSyslogSeverity());
}

// ============================================================================
// Level Parsing Tests
// ============================================================================

test "Level.parse - valid inputs" {
    try std.testing.expectEqual(Level.trace, Level.parse("trace").?);
    try std.testing.expectEqual(Level.debug, Level.parse("debug").?);
    try std.testing.expectEqual(Level.info, Level.parse("info").?);
    try std.testing.expectEqual(Level.warn, Level.parse("warn").?);
    try std.testing.expectEqual(Level.@"error", Level.parse("error").?);
    try std.testing.expectEqual(Level.fatal, Level.parse("fatal").?);
}

test "Level.parse - case insensitive" {
    try std.testing.expectEqual(Level.trace, Level.parse("TRACE").?);
    try std.testing.expectEqual(Level.debug, Level.parse("DEBUG").?);
    try std.testing.expectEqual(Level.info, Level.parse("INFO").?);
    try std.testing.expectEqual(Level.warn, Level.parse("WARN").?);
    try std.testing.expectEqual(Level.@"error", Level.parse("ERROR").?);
    try std.testing.expectEqual(Level.fatal, Level.parse("FATAL").?);
}

test "Level.parse - mixed case" {
    try std.testing.expectEqual(Level.trace, Level.parse("Trace").?);
    try std.testing.expectEqual(Level.info, Level.parse("Info").?);
    try std.testing.expectEqual(Level.warn, Level.parse("WaRn").?);
}

test "Level.parse - invalid inputs" {
    try std.testing.expect(Level.parse("invalid") == null);
    try std.testing.expect(Level.parse("") == null);
    try std.testing.expect(Level.parse("err") == null);
    try std.testing.expect(Level.parse("inf") == null);
    try std.testing.expect(Level.parse("errorr") == null);
}

test "Level.parse - warning alias" {
    // "warning" is a valid alias for "warn"
    try std.testing.expectEqual(Level.warn, Level.parse("warning").?);
    try std.testing.expectEqual(Level.warn, Level.parse("WARNING").?);
}

// ============================================================================
// Level Comparison Tests
// ============================================================================

test "Level comparison operators" {
    try std.testing.expect(@intFromEnum(Level.trace) < @intFromEnum(Level.debug));
    try std.testing.expect(@intFromEnum(Level.debug) < @intFromEnum(Level.info));
    try std.testing.expect(@intFromEnum(Level.info) < @intFromEnum(Level.warn));
    try std.testing.expect(@intFromEnum(Level.warn) < @intFromEnum(Level.@"error"));
    try std.testing.expect(@intFromEnum(Level.@"error") < @intFromEnum(Level.fatal));
}
