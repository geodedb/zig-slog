//! Comprehensive unit tests for all handlers.

const std = @import("std");
const slogz = @import("slogz");
const Record = slogz.Record;
const Attr = slogz.Attr;
const Level = slogz.Level;
const Clock = slogz.Clock;
const Handler = slogz.Handler;

// ============================================================================
// Discard Handler Tests
// ============================================================================

test "DiscardHandler - handles all levels" {
    const handler = slogz.discardHandler();

    const levels = [_]Level{ .trace, .debug, .info, .warn, .@"error", .fatal };
    for (levels) |level| {
        const rec = Record{
            .time_utc_us = 1735787045000000,
            .level = level,
            .msg_id = "test",
            .message = "test message",
            .logger = "test",
            .source_file = "",
            .source_line = 0,
            .attrs = &.{},
        };
        try handler.handle(&rec);
    }
}

test "DiscardHandler - handles many attributes" {
    const handler = slogz.discardHandler();

    var attrs: [32]Attr = undefined;
    for (&attrs, 0..) |*attr, i| {
        attr.* = Attr.int("key", @intCast(i));
    }

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &attrs,
    };

    try handler.handle(&rec);
}

test "DiscardHandler - flush does nothing" {
    const handler = slogz.discardHandler();
    try handler.flush(1000);
}

test "DiscardHandler - withAttrs returns handler" {
    const handler = slogz.discardHandler();
    const derived = handler.withAttrs(&.{Attr.string("key", "value")});
    try derived.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });
}

test "DiscardHandler - withGroup returns handler" {
    const handler = slogz.discardHandler();
    const derived = handler.withGroup("group");
    try derived.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });
}

// ============================================================================
// Text Handler Tests
// ============================================================================

test "TextHandler - level filtering" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.text.Context.init(fbs.writer().any(), .warn, Clock.system());
    const handler = slogz.text.init(&ctx);

    // Debug should be filtered
    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .debug,
        .msg_id = "test",
        .message = "debug message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });
    try std.testing.expectEqual(@as(usize, 0), fbs.getWritten().len);

    // Warn should pass
    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .warn,
        .msg_id = "test",
        .message = "warn message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });
    try std.testing.expect(fbs.getWritten().len > 0);
}

test "TextHandler - all value types" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.text.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.text.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "test",
        .message = "Testing all types",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("str", "hello"),
            Attr.int("int", -42),
            Attr.uint("uint", 42),
            Attr.float("float", 3.14159),
            Attr.boolean("bool_true", true),
            Attr.boolean("bool_false", false),
            Attr.bytes("bytes", &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }),
            Attr.err("error", error.TestError),
            Attr.secret("secret", "hidden_value"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "str=hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "int=-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "uint=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "float=3.14") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bool_true=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bool_false=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bytes=0xdeadbeef") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "error=TestError") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[REDACTED]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "hidden_value") == null);
}

test "TextHandler - quoted strings with spaces" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.text.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.text.init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("path", "hello world"),
            Attr.string("eq", "key=value"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "path=\"hello world\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "eq=\"key=value\"") != null);
}

test "TextHandler - special float values" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.text.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.text.init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.float("nan", std.math.nan(f64)),
            Attr.float("inf", std.math.inf(f64)),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // NaN and Inf should be rendered as null
    try std.testing.expect(std.mem.indexOf(u8, output, "nan=null") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "inf=null") != null);
}

test "TextHandler - dynamic level change" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.text.Context.init(fbs.writer().any(), .@"error", Clock.system());
    const handler = slogz.text.init(&ctx);

    // Info should be filtered at error level
    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "info",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });
    try std.testing.expectEqual(@as(usize, 0), fbs.getWritten().len);

    // Change level to info
    handler.setLevel(.info);

    // Now info should pass
    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "info",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });
    try std.testing.expect(fbs.getWritten().len > 0);
}

// ============================================================================
// JSON Handler Tests
// ============================================================================

test "JSONHandler - valid JSON output" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.json.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "test.json",
        .message = "JSON test",
        .logger = "test",
        .source_file = "test.zig",
        .source_line = 42,
        .attrs = &.{
            Attr.string("key", "value"),
            Attr.int("num", 123),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // Verify starts with { and ends with }\n
    try std.testing.expect(output.len > 0);
    try std.testing.expectEqual(@as(u8, '{'), output[0]);
    try std.testing.expectEqual(@as(u8, '\n'), output[output.len - 1]);
    try std.testing.expectEqual(@as(u8, '}'), output[output.len - 2]);
}

test "JSONHandler - level filtering" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.json.Context.init(fbs.writer().any(), .@"error", Clock.system());
    const handler = slogz.json.init(&ctx);

    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "should be filtered",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    try std.testing.expectEqual(@as(usize, 0), fbs.getWritten().len);
}

test "JSONHandler - escape special characters" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.json.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "Line1\nLine2\tTab\\Backslash\"Quote",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "\\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\\\") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\\"") != null);
}

test "JSONHandler - control character escaping" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.json.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "control:\x01\x02\x03",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // Control chars should be escaped as \uXXXX
    try std.testing.expect(std.mem.indexOf(u8, output, "\\u") != null);
}

test "JSONHandler - all value types" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.json.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("str", "hello"),
            Attr.int("int", -42),
            Attr.uint("uint", 42),
            Attr.float("float", 3.14),
            Attr.boolean("bool", true),
            Attr.err("error", error.SomeError),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"str\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"int\":-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"uint\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"float\":3.14") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"bool\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"error\":\"SomeError\"") != null);
}

test "JSONHandler - no source info when empty" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.json.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // Should not have source when source_file is empty
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source\"") == null);
}

test "JSONHandler - with source info" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.json.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "main.zig",
        .source_line = 100,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"source\":{\"file\":\"main.zig\",\"line\":100}") != null);
}

// ============================================================================
// Syslog RFC5424 Handler Tests
// ============================================================================

test "SyslogHandler - PRI calculation" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // local0 = 16, info severity = 6
    // PRI = 16 * 8 + 6 = 134
    var ctx = slogz.syslog.Context.init(fbs.writer().any(), .info, Clock.system(), .{
        .facility = .local0,
        .hostname = "testhost",
    });
    const handler = slogz.syslog.init(&ctx);

    try handler.handle(&Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, output, "<134>1 "));
}

test "SyslogHandler - error level PRI" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // local0 = 16, error severity = 3
    // PRI = 16 * 8 + 3 = 131
    var ctx = slogz.syslog.Context.init(fbs.writer().any(), .info, Clock.system(), .{
        .facility = .local0,
        .hostname = "testhost",
    });
    const handler = slogz.syslog.init(&ctx);

    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .@"error",
        .msg_id = "test",
        .message = "error message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, output, "<131>1 "));
}

test "SyslogHandler - structured data escaping" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.syslog.Context.init(fbs.writer().any(), .info, Clock.system(), .{
        .hostname = "host",
    });
    const handler = slogz.syslog.init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("special", "test\"quote]bracket\\backslash"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // RFC5424 requires escaping: \ " ]
    try std.testing.expect(std.mem.indexOf(u8, output, "\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\\\") != null);
}

test "SyslogHandler - all facility types" {
    const facilities = [_]slogz.syslog.Facility{
        .kern, .user, .mail, .daemon, .auth, .syslog, .lpr, .news,
        .uucp, .cron, .authpriv, .ftp, .ntp, .audit, .alert, .clock,
        .local0, .local1, .local2, .local3, .local4, .local5, .local6, .local7,
    };

    for (facilities) |facility| {
        var buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);

        var ctx = slogz.syslog.Context.init(fbs.writer().any(), .info, Clock.system(), .{
            .facility = facility,
            .hostname = "host",
        });
        const handler = slogz.syslog.init(&ctx);

        try handler.handle(&Record{
            .time_utc_us = 0,
            .level = .info,
            .msg_id = "test",
            .message = "test",
            .logger = "",
            .source_file = "",
            .source_line = 0,
            .attrs = &.{},
        });

        try std.testing.expect(fbs.getWritten().len > 0);
    }
}

test "SyslogHandler - procid included" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.syslog.Context.init(fbs.writer().any(), .info, Clock.system(), .{
        .hostname = "host",
        .procid = 12345,
    });
    const handler = slogz.syslog.init(&ctx);

    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, " 12345 ") != null);
}

test "SyslogHandler - nilvalue for missing fields" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = slogz.syslog.Context.init(fbs.writer().any(), .info, Clock.system(), .{
        .hostname = "-",
        .app_name = "-",
        .procid = null,
    });
    const handler = slogz.syslog.init(&ctx);

    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    const output = fbs.getWritten();
    // Should have multiple NILVALUE markers
    try std.testing.expect(std.mem.indexOf(u8, output, "- - - -") != null);
}

// ============================================================================
// Handler Interface Tests
// ============================================================================

test "Handler - vtable consistency" {
    const discard = slogz.discardHandler();

    // Verify all vtable functions are present by calling them
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try discard.handle(&rec);
    try discard.flush(0);
    discard.setLevel(.debug);
    _ = discard.withAttrs(&.{});
    _ = discard.withGroup("group");
}

test "Handler - polymorphic behavior" {
    // Test that different handlers can be used interchangeably
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var text_ctx = slogz.text.Context.init(fbs.writer().any(), .info, Clock.system());
    const handlers = [_]Handler{
        slogz.discardHandler(),
        slogz.text.init(&text_ctx),
    };

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    for (handlers) |handler| {
        try handler.handle(&rec);
        try handler.flush(0);
    }
}
