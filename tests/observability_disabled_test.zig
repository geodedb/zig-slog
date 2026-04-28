// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Verifies the no-op invariant when -Dwith_otel=false (the default).
//!
//! slog is a BUILD-FLAG-ONLY otel consumer: the seam scaffolding exists for
//! forward compatibility, but slog itself never calls into the seam (doing so
//! would risk a logging->span->logging feedback loop, since otel's std.log
//! bridge can route back through slog when slog is otel's logger backend).
//! See README.md "Observability" for the rationale.

const std = @import("std");
const slogz = @import("slogz");

test "build_options.with_otel exists and defaults to false" {
    const build_options = @import("build_options");
    try std.testing.expect(@hasDecl(build_options, "with_otel"));
    // The "default" assertion only holds for the disabled build. When
    // the operator forces -Dwith_otel=true, this test runs against the
    // enabled module and must skip rather than misreport the default.
    if (build_options.with_otel) return error.SkipZigTest;
    try std.testing.expectEqual(false, build_options.with_otel);
}

test "observability.enabled tracks build_options.with_otel" {
    const build_options = @import("build_options");
    try std.testing.expectEqual(build_options.with_otel, slogz.observability.enabled);
}

test "no-op when otel disabled" {
    if (slogz.observability.enabled) return error.SkipZigTest;
    var span = slogz.observability.startClientSpan(.{
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
    // Belt-and-suspenders: callers may also invoke `span.end(null)`
    // directly. The seam's `endClientSpan` already covers the lifecycle;
    // this line just verifies the no-op fallback signature matches the
    // real API's `Span.end(?u64) void`.
    span.end(null);
}
