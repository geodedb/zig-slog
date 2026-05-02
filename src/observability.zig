// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! observability.zig - single-file otel seam.
//!
//! When build_options.with_otel == false, every public function in this file
//! collapses to a comptime-known no-op so the optimizer eliminates the call
//! site entirely. When true, calls forward to the appropriate
//! `otel.api.trace`/`otel.instrumentation.http` helper.
//!
//! INVARIANT: every emit is `catch {}`-discarded. A failing exporter never
//! reaches the caller.
//!
//! NOTE: slog is a structured-logging library and otel's transitive
//! dependency (otel routes std.log through a slog backend when
//! `-Dotel_use_devnw_slog=true`). For that reason slog is BUILD-FLAG ONLY:
//! NO source file in slog calls into the seam. Adding span emission to
//! slog's log path would create a logging->span->logging feedback loop and
//! a dependency cycle. The seam is exposed so a `-Dwith_otel=true` build
//! still resolves cleanly and so consumers/embedders can wire spans
//! around their own slog interactions if useful.

const std = @import("std");
// 2026-05-02: hardcoded enabled=false and removed the build_options
// import + the conditional otel import. The previous pattern surfaced
// a Zig 0.16 module-dedup quirk when the lib was reached through
// multiple paths in a downstream build graph (geode), producing
// "build_options" vs "build_options0" diamonds at this file. The
// seam is preserved as a permanent no-op for forward-compat;
// restore the conditional once the upstream Zig dedup issue is
// resolved.
pub const enabled: bool = false;

const otel = struct {};

/// Opaque handle for an in-flight operation. When disabled, this is a
/// zero-sized struct the optimizer drops entirely. The no-op fallback's
/// `end` signature MUST match `otel.api.trace.Span.end(?u64) void` so
/// callers can write `span.end(null)` regardless of `enabled` state.
pub const Span = if (enabled) otel.api.trace.Span else struct {
    pub fn end(self: @This(), _: ?u64) void {
        _ = self;
    }
};

/// Start a span for an outbound operation. The caller passes anything with
/// `method_string()` and `url_string()` accessors.
pub fn startClientSpan(req: anytype) Span {
    if (!enabled) return Span{};
    const tracer = global.tracer orelse return Span{};
    const span = otel.instrumentation.http.startClientSpan(
        tracer.*,
        .empty(),
        .{
            .method = req.method_string(),
            .url = req.url_string(),
        },
    ) catch return Span{};
    return span;
}

pub fn endClientSpan(span: Span, status: u16) void {
    if (!enabled) return;
    otel.instrumentation.http.endClientSpan(span, .{ .status_code = status });
}

/// Start a span for an inbound operation. The caller passes anything with
/// `method_string()`, `route_string()`, and `url_string()` accessors. The
/// duck-typed anytype shape is never invoked by slog code itself - it
/// matches the canonical seam shape so consumers can wire it from their
/// own server-side code if useful.
pub fn startServerSpan(req: anytype) Span {
    if (!enabled) return Span{};
    const tracer = global.tracer orelse return Span{};
    const span = otel.instrumentation.http.startServerSpan(
        tracer.*,
        .empty(),
        .{
            .method = req.method_string(),
            .route = req.route_string(),
            .url = req.url_string(),
        },
    ) catch return Span{};
    return span;
}

pub fn endServerSpan(span: Span, status: u16) void {
    if (!enabled) return;
    otel.instrumentation.http.endServerSpan(span, status);
}

/// Set once at process start by `observability_init.Otel.init`. Only
/// referenced when enabled is true; otherwise the optimizer drops it.
pub const global = if (enabled) struct {
    pub var tracer: ?*otel.api.trace.Tracer = null;
    pub var meter: ?*otel.api.metrics.Meter = null;
} else struct {};
