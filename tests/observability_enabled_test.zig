// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Verifies one client span lands in an in-memory recorder when
//! -Dwith_otel=true.
//!
//! Because slog is build-flag-only (no slog source file calls into the
//! seam - doing so would risk a logging->span->logging feedback loop),
//! this is a degenerate "seam compiles and wires correctly" test rather
//! than a "slog emits a span on some operation" test. It instantiates a
//! TracerProvider, points `slogz.observability.global.tracer` at it,
//! calls `startClientSpan` directly with a duck-typed request, and
//! asserts the in-memory recorder saw exactly one span. This proves
//! the seam is wired correctly even though no slog source file calls it.

const std = @import("std");
const build_options = @import("build_options");
const slogz = @import("slogz");

// The `otel` module is only added to this test root when
// `-Dwith_otel=true`. To compile cleanly under both flag values we
// gate the import behind a comptime conditional and stub the alias to
// an empty struct when the flag is off - that branch is dead code in
// the disabled build but the import expression resolves.
const otel = if (build_options.with_otel) @import("otel") else struct {};

test "one span recorded when otel enabled" {
    if (!slogz.observability.enabled) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var resource = try otel.sdk.resource.defaultResource(allocator);
    defer resource.deinit();
    try resource.attributes.putString(otel.semconv.service_name, "slog-test");

    var recorder = otel.exporters.in_memory.Recorder.init(allocator);
    defer recorder.deinit();
    var tp = try otel.sdk.trace.TracerProvider.init(allocator, .{
        .resource = &resource,
        .default_exporter = recorder.spanExporter(),
    });
    defer tp.deinit();

    var tracer = tp.tracer(.{ .name = "slog-test" });
    slogz.observability.global.tracer = &tracer;
    defer slogz.observability.global.tracer = null;

    const span = slogz.observability.startClientSpan(.{
        .method_string = struct {
            fn s() []const u8 {
                return "GET";
            }
        }.s,
        .url_string = struct {
            fn s() []const u8 {
                return "https://x";
            }
        }.s,
    });
    slogz.observability.endClientSpan(span, 200);

    try tp.forceFlush(1_000);
    try std.testing.expectEqual(@as(usize, 1), recorder.spans.items.len);
}
