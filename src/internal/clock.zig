// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Clock abstraction for time-related operations.
//!
//! Supports both real system time and fixed clocks for testing.

const std = @import("std");

/// Clock interface for getting current UTC time.
pub const Clock = struct {
    nowUtcMicros: *const fn () i128,

    /// Creates a clock using the system time.
    pub fn system() Clock {
        return .{ .nowUtcMicros = systemNowUtcMicros };
    }

    /// Creates a fixed clock for testing.
    pub fn fixed(timestamp_us: i128) FixedClock {
        return FixedClock.init(timestamp_us);
    }

    /// Gets current UTC time in microseconds since epoch.
    pub fn now(self: Clock) i128 {
        return self.nowUtcMicros();
    }
};

/// A fixed clock that always returns the same timestamp.
///
/// Because Zig function pointers cannot capture state, the fixed timestamp
/// is stored in a thread-local variable. Calling `init` or `setFixedTimestamp`
/// sets that thread-local. The returned `Clock` reads it back via the
/// function pointer, so each thread can have its own fixed time.
pub const FixedClock = struct {
    clock: Clock,

    pub fn init(timestamp_us: i128) FixedClock {
        setFixedTimestamp(timestamp_us);
        return .{
            .clock = .{ .nowUtcMicros = getFixedTimestamp },
        };
    }

    pub fn asClock(self: *const FixedClock) Clock {
        _ = self;
        return .{ .nowUtcMicros = getFixedTimestamp };
    }
};

// Thread-local fixed timestamp for testing
threadlocal var fixed_test_timestamp: i128 = 0;

fn getFixedTimestamp() i128 {
    return fixed_test_timestamp;
}

/// Set the fixed timestamp for testing (thread-local).
pub fn setFixedTimestamp(timestamp_us: i128) void {
    fixed_test_timestamp = timestamp_us;
}

fn systemNowUtcMicros() i128 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ns = std.Io.Clock.real.now(io).nanoseconds;
    return @divFloor(@as(i128, ns), std.time.ns_per_us);
}

/// Parses ISO8601 timestamp to microseconds since epoch.
pub fn parseIso8601ToMicros(s: []const u8) ?i128 {
    // Format: 2025-01-02T03:04:05.000000Z
    if (s.len < 20) return null;

    const year = std.fmt.parseInt(i32, s[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, s[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, s[8..10], 10) catch return null;
    const hour = std.fmt.parseInt(u8, s[11..13], 10) catch return null;
    const minute = std.fmt.parseInt(u8, s[14..16], 10) catch return null;
    const second = std.fmt.parseInt(u8, s[17..19], 10) catch return null;

    var micros: i128 = 0;
    if (s.len > 20 and s[19] == '.') {
        // Parse fractional seconds
        var end: usize = 20;
        while (end < s.len and s[end] >= '0' and s[end] <= '9') : (end += 1) {}
        const frac_str = s[20..end];
        var frac: i128 = std.fmt.parseInt(i128, frac_str, 10) catch 0;
        // Pad or truncate to 6 digits
        var digits = frac_str.len;
        while (digits < 6) : (digits += 1) frac *= 10;
        while (digits > 6) : (digits -= 1) frac = @divTrunc(frac, 10);
        micros = frac;
    }

    // Convert to epoch seconds
    const epoch_days = epochDays(year, month, day);
    const epoch_secs: i128 = epoch_days * 86400 + @as(i128, hour) * 3600 + @as(i128, minute) * 60 + @as(i128, second);

    return epoch_secs * 1_000_000 + micros;
}

pub fn epochDays(year: i32, month: u8, day: u8) i64 {
    // Days from Unix epoch (1970-01-01)
    var y: i64 = @intCast(year);
    var m: i64 = @intCast(month);
    const d: i64 = @intCast(day);

    // Adjust for months before March
    if (m <= 2) {
        y -= 1;
        m += 12;
    }

    const era: i64 = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe: i64 = y - era * 400;
    const doy: i64 = @divFloor(153 * (m - 3) + 2, 5) + d - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;

    return era * 146097 + doe - 719468;
}

test "parseIso8601ToMicros" {
    const ts = parseIso8601ToMicros("2025-01-02T03:04:05.000000Z");
    try std.testing.expect(ts != null);
    // 2025-01-02T03:04:05.000000Z should be a valid timestamp
}

test "Clock.system" {
    const clock = Clock.system();
    const now = clock.now();
    try std.testing.expect(now > 0);
}

test "FixedClock.init sets thread-local and returns correct timestamp" {
    const expected: i128 = 1735787045000000;
    const fc = FixedClock.init(expected);
    const clock = fc.asClock();

    try std.testing.expectEqual(expected, clock.now());

    // Verify init with a different value updates the thread-local.
    const expected2: i128 = 9999999;
    _ = FixedClock.init(expected2);
    try std.testing.expectEqual(expected2, clock.now());
}

test "Clock.fixed returns FixedClock with correct timestamp" {
    const expected: i128 = 42000000;
    const fc = Clock.fixed(expected);
    try std.testing.expectEqual(expected, fc.clock.now());
}
