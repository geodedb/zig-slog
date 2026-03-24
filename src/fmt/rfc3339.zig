// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! RFC3339 timestamp formatting with microsecond precision.
//!
//! Produces timestamps in the format: 2025-01-02T03:04:05.000000Z

const std = @import("std");
const clock = @import("../internal/clock.zig");

/// Format a timestamp in microseconds since epoch to RFC3339 format.
/// Output format: YYYY-MM-DDTHH:MM:SS.ffffffZ (27 bytes)
pub fn formatTimestamp(buf: *[27]u8, time_utc_us: i128) void {
    // Handle the timestamp - must be non-negative for proper calculation
    const timestamp: u64 = if (time_utc_us < 0) 0 else @intCast(@min(time_utc_us, std.math.maxInt(u64)));

    const secs: u64 = timestamp / 1_000_000;
    const micros: u32 = @intCast(timestamp % 1_000_000);

    // Convert to date/time components
    const days: i64 = @intCast(secs / 86400);
    const day_secs: u32 = @intCast(secs % 86400);

    const ymd = epochDayToYmd(days);
    const hour: u32 = day_secs / 3600;
    const minute: u32 = (day_secs % 3600) / 60;
    const second: u32 = day_secs % 60;

    // Format manually to avoid signed number formatting issues
    // Year (4 digits)
    const year: u32 = @intCast(if (ymd.year < 0) 0 else ymd.year);
    buf[0] = '0' + @as(u8, @intCast((year / 1000) % 10));
    buf[1] = '0' + @as(u8, @intCast((year / 100) % 10));
    buf[2] = '0' + @as(u8, @intCast((year / 10) % 10));
    buf[3] = '0' + @as(u8, @intCast(year % 10));
    buf[4] = '-';

    // Month (2 digits)
    buf[5] = '0' + @as(u8, @intCast(ymd.month / 10));
    buf[6] = '0' + @as(u8, @intCast(ymd.month % 10));
    buf[7] = '-';

    // Day (2 digits)
    buf[8] = '0' + @as(u8, @intCast(ymd.day / 10));
    buf[9] = '0' + @as(u8, @intCast(ymd.day % 10));
    buf[10] = 'T';

    // Hour (2 digits)
    buf[11] = '0' + @as(u8, @intCast(hour / 10));
    buf[12] = '0' + @as(u8, @intCast(hour % 10));
    buf[13] = ':';

    // Minute (2 digits)
    buf[14] = '0' + @as(u8, @intCast(minute / 10));
    buf[15] = '0' + @as(u8, @intCast(minute % 10));
    buf[16] = ':';

    // Second (2 digits)
    buf[17] = '0' + @as(u8, @intCast(second / 10));
    buf[18] = '0' + @as(u8, @intCast(second % 10));
    buf[19] = '.';

    // Microseconds (6 digits)
    buf[20] = '0' + @as(u8, @intCast((micros / 100000) % 10));
    buf[21] = '0' + @as(u8, @intCast((micros / 10000) % 10));
    buf[22] = '0' + @as(u8, @intCast((micros / 1000) % 10));
    buf[23] = '0' + @as(u8, @intCast((micros / 100) % 10));
    buf[24] = '0' + @as(u8, @intCast((micros / 10) % 10));
    buf[25] = '0' + @as(u8, @intCast(micros % 10));
    buf[26] = 'Z';
}

/// Write timestamp to a writer.
pub fn writeTimestamp(writer: anytype, time_utc_us: i128) !void {
    var buf: [27]u8 = undefined;
    formatTimestamp(&buf, time_utc_us);
    try writer.writeAll(&buf);
}

const YearMonthDay = struct {
    year: i32,
    month: u8,
    day: u8,
};

fn epochDayToYmd(epoch_day: i128) YearMonthDay {
    // Algorithm from https://howardhinnant.github.io/date_algorithms.html
    const z: i64 = @intCast(epoch_day + 719468);
    const era: i64 = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: u64 = @intCast(z - era * 146097);
    const yoe: u64 = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
    const y: i64 = @as(i64, @intCast(yoe)) + era * 400;
    const doy: u64 = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100));
    const mp: u64 = @divTrunc(5 * doy + 2, 153);
    const d: u64 = doy - @divTrunc(153 * mp + 2, 5) + 1;
    const m: u64 = if (mp < 10) mp + 3 else mp - 9;

    return .{
        .year = @intCast(if (m <= 2) y + 1 else y),
        .month = @intCast(m),
        .day = @intCast(d),
    };
}

/// Parse RFC3339 timestamp to microseconds since epoch.
pub fn parseTimestamp(s: []const u8) ?i128 {
    if (s.len < 20) return null;
    if (s[4] != '-' or s[7] != '-' or s[10] != 'T' or s[13] != ':' or s[16] != ':') return null;

    const year = std.fmt.parseInt(i32, s[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, s[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, s[8..10], 10) catch return null;
    const hour = std.fmt.parseInt(u8, s[11..13], 10) catch return null;
    const minute = std.fmt.parseInt(u8, s[14..16], 10) catch return null;
    const second = std.fmt.parseInt(u8, s[17..19], 10) catch return null;

    if (month < 1 or month > 12 or day < 1 or day > 31) return null;
    if (hour > 23 or minute > 59 or second > 60) return null;

    var micros: i64 = 0;
    if (s.len > 20 and s[19] == '.') {
        var end: usize = 20;
        while (end < s.len and s[end] >= '0' and s[end] <= '9') : (end += 1) {}
        const frac_str = s[20..end];
        if (frac_str.len > 0) {
            var frac: i64 = std.fmt.parseInt(i64, frac_str, 10) catch 0;
            var digits = frac_str.len;
            while (digits < 6) : (digits += 1) frac *= 10;
            while (digits > 6) : (digits -= 1) frac = @divTrunc(frac, 10);
            micros = frac;
        }
    }

    const epoch_days = clock.epochDays(year, month, day);
    const epoch_secs: i128 = epoch_days * 86400 + @as(i128, hour) * 3600 + @as(i128, minute) * 60 + @as(i128, second);

    return epoch_secs * 1_000_000 + micros;
}

test "formatTimestamp" {
    // 2025-01-02T03:04:05.000000Z
    const timestamp: i128 = 1735787045000000; // Approximate
    var buf: [27]u8 = undefined;
    formatTimestamp(&buf, timestamp);

    try std.testing.expect(buf[0] == '2');
    try std.testing.expect(buf[4] == '-');
    try std.testing.expect(buf[10] == 'T');
    try std.testing.expect(buf[26] == 'Z');
}

test "parseTimestamp roundtrip" {
    const original = "2025-01-02T03:04:05.123456Z";
    const parsed = parseTimestamp(original);
    try std.testing.expect(parsed != null);

    var buf: [27]u8 = undefined;
    formatTimestamp(&buf, parsed.?);
    try std.testing.expectEqualStrings(original, &buf);
}
