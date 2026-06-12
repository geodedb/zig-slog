// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Feature flags
    const feature_journald = b.option(bool, "feature_journald", "Enable journald support (requires libsystemd)") orelse false;
    const feature_windows_eventlog = b.option(bool, "feature_windows_eventlog", "Enable Windows Event Log support") orelse false;

    // Thread-pool parallelism option
    const enable_tp = b.option(bool, "enable_tp", "Enable thread-pool-based parallelism") orelse true;

    // -Dwith_otel=<bool> compiles in the otel observability seam. When
    // false (the default), the otel dependency is never resolved and no
    // otel symbols are imported - the produced module contains zero
    // `otel`/`observability` linked symbols. Verified by
    // otel/scripts/verify-consumer-noop.sh.
    //
    // slog is BUILD-FLAG ONLY: even with `-Dwith_otel=true`, slog itself
    // does not call into the seam. slog is otel's transitive std.log
    // backend (under `-Dotel_use_devnw_slog=true`), so a slog-emitted
    // span would risk a logging->span->logging feedback loop. The flag +
    // seam exist for forward compatibility and consumer-side wiring.
    const with_otel = false; // 2026-05-02: hardcoded after removing the lazy otel dep — see build.zig.zon header note.

    // Forward otel build options so the upstream package is configured
    // identically across all consumers in the build graph. Without this,
    // each consumer's `b.lazyDependency("otel", ...)` materialises a
    // DISTINCT otel Module instance (different `build_options` ⇒ different
    // package keys), and zig 0.16 errors with `file exists in modules
    // 'otel' and 'otel0'` when transitive imports overlap.
    const otel_use_devnw_tls = b.option(
        bool,
        "otel_use_devnw_tls",
        "Forward to upstream otel: HTTPS via DevNW tls",
    ) orelse false;
    const otel_disabled = b.option(
        bool,
        "otel_disabled",
        "Forward to upstream otel: comptime-disable",
    ) orelse false;
    const otel_profiles = b.option(
        bool,
        "otel_profiles",
        "Forward to upstream otel: experimental profiles",
    ) orelse false;
    const otel_use_devnw_grpc = b.option(
        bool,
        "otel_use_devnw_grpc",
        "Forward to upstream otel: DevNW gRPC",
    ) orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "feature_journald", feature_journald);
    build_options.addOption(bool, "feature_windows_eventlog", feature_windows_eventlog);
    build_options.addOption([]const u8, "package_name", "slog");
    build_options.addOption(bool, "with_otel", with_otel);
    // Shared `build_options` module - every artifact that imports
    // `slogz` AND needs `build_options` (the slogz module itself, the
    // observability seam reached through it, the observability tests)
    // must reach the SAME module instance. Reaching the same source
    // file via two distinct module instances is a hard compile error
    // in Zig.
    const build_options_mod = build_options.createModule();

    // Get thread_pool dependency if enabled
    const tp_mod: ?*std.Build.Module = if (enable_tp) blk: {
        const tp_dep = b.dependency("thread_pool", .{
            .target = target,
            .optimize = optimize,
        });
        break :blk tp_dep.module("thread_pool");
    } else null;

    // Get dependencies
    const use_json = b.option(bool, "json", "Use internal json dependency") orelse true;
    const json_mod: ?*std.Build.Module = if (use_json) blk: {
        const json_dep = b.dependency("json", .{
            .target = target,
            .optimize = optimize,
        });
        break :blk json_dep.module("json");
    } else null;

    // Main module (parallel.zig is part of the slogz module via relative import)
    const slogz_mod = b.addModule("slogz", .{
        .root_source_file = b.path("src/slogz.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (json_mod) |m| slogz_mod.addImport("json", m);
    if (tp_mod) |sm| {
        slogz_mod.addImport("thread_pool", sm);
    }
    // The slogz public root re-exports `observability` and
    // `observability_init`, both of which @import("build_options").
    // Share the single instance so every test/bench artifact that
    // reaches src/slogz.zig sees the same module graph.
    slogz_mod.addImport("build_options", build_options_mod);

    // Link libsystemd if journald is enabled
    if (feature_journald) {
        slogz_mod.linkSystemLibrary("systemd", .{});
    }

    // Named `observability` module - exposed both as a re-export from
    // src/slogz.zig (`slogz.observability`) AND as a standalone named
    // module so consumers can `dep.module("observability")` directly if
    // they prefer the seam without pulling in the rest of slog. Per the
    // otel rollout RECIPE the named-module pattern is required.
    const observability_mod = b.addModule("observability", .{
        .root_source_file = b.path("src/observability.zig"),
        .target = target,
        .optimize = optimize,
    });
    observability_mod.addImport("build_options", build_options_mod);

    // When -Dwith_otel=true, resolve the otel dependency and surface it
    // to both the slogz module and the standalone observability module.
    // The lazy() call only triggers a fetch when the flag is true; the
    // disabled build never reaches the dependency resolver, so the otel
    // package never shows up on disk. slog itself does not call any
    // seam function - the seam is exposed for consumer-side wiring and
    // forward compatibility (see observability.zig header).
    if (with_otel) {
        if (b.lazyDependency("otel", .{
            .target = target,
            .optimize = optimize,
            .otel_use_devnw_tls = otel_use_devnw_tls,
            .otel_disabled = otel_disabled,
            .otel_profiles = otel_profiles,
            .otel_use_devnw_grpc = otel_use_devnw_grpc,
        })) |otel_dep| {
            slogz_mod.addImport("otel", otel_dep.module("otel"));
            observability_mod.addImport("otel", otel_dep.module("otel"));
        }
    }

    // Unit tests (source tests)
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/slogz.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    if (json_mod) |m| unit_tests.root_module.addImport("json", m);
    if (tp_mod) |sm| {
        unit_tests.root_module.addImport("thread_pool", sm);
    }
    // src/slogz.zig re-exports observability + observability_init,
    // both of which @import("build_options"). The unit_tests artifact
    // creates its own module instance pointing at src/slogz.zig, so it
    // needs the same build_options module attached.
    unit_tests.root_module.addImport("build_options", build_options_mod);
    if (with_otel) {
        if (b.lazyDependency("otel", .{
            .target = target,
            .optimize = optimize,
            .otel_use_devnw_tls = otel_use_devnw_tls,
            .otel_disabled = otel_disabled,
            .otel_profiles = otel_profiles,
            .otel_use_devnw_grpc = otel_use_devnw_grpc,
        })) |otel_dep| {
            unit_tests.root_module.addImport("otel", otel_dep.module("otel"));
        }
    }
    if (feature_journald) {
        unit_tests.root_module.linkSystemLibrary("systemd", .{});
    }

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_unit_tests.step);

    // Acceptance tests
    const accept_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/accept.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
            },
        }),
    });
    if (feature_journald) {
        accept_tests.root_module.linkSystemLibrary("systemd", .{});
    }

    const run_accept_tests = b.addRunArtifact(accept_tests);
    test_step.dependOn(&run_accept_tests.step);

    // Level tests
    const level_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/level_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
            },
        }),
    });
    const run_level_tests = b.addRunArtifact(level_tests);
    test_step.dependOn(&run_level_tests.step);

    // Value tests
    const value_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/value_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
            },
        }),
    });
    const run_value_tests = b.addRunArtifact(value_tests);
    test_step.dependOn(&run_value_tests.step);

    // Record tests
    const record_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/record_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
            },
        }),
    });
    const run_record_tests = b.addRunArtifact(record_tests);
    test_step.dependOn(&run_record_tests.step);

    // Handler tests
    const handler_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/handler_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
            },
        }),
    });
    const run_handler_tests = b.addRunArtifact(handler_tests);
    test_step.dependOn(&run_handler_tests.step);

    // Sink tests
    const sink_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sink_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
            },
        }),
    });
    const run_sink_tests = b.addRunArtifact(sink_tests);
    test_step.dependOn(&run_sink_tests.step);

    // Observability disabled-no-op test - asserts the seam compiles to
    // zero work when -Dwith_otel=false (and skips the assertion when
    // forced on). The test imports `build_options` directly to inspect
    // the flag, so we attach the SAME shared module instance the
    // slogz_mod uses. When -Dwith_otel=true, the lazy otel dep is
    // surfaced so the seam's @import("otel") inside src/observability.zig
    // (reached transitively through slogz) resolves.
    const observability_disabled_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/observability_disabled_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
                .{ .name = "build_options", .module = build_options_mod },
            },
        }),
    });
    if (with_otel) {
        if (b.lazyDependency("otel", .{
            .target = target,
            .optimize = optimize,
            .otel_use_devnw_tls = otel_use_devnw_tls,
            .otel_disabled = otel_disabled,
            .otel_profiles = otel_profiles,
            .otel_use_devnw_grpc = otel_use_devnw_grpc,
        })) |otel_dep| {
            observability_disabled_tests.root_module.addImport("otel", otel_dep.module("otel"));
        }
    }
    const run_observability_disabled_tests = b.addRunArtifact(observability_disabled_tests);
    test_step.dependOn(&run_observability_disabled_tests.step);

    // Observability enabled-mode smoke test - skipped under
    // -Dwith_otel=false (the test body returns SkipZigTest when
    // `slogz.observability.enabled` is false). Under
    // -Dwith_otel=true the lazy otel dep is resolved and the test
    // exercises the seam directly: it points
    // `slogz.observability.global.tracer` at an in-memory recorder,
    // calls `startClientSpan` with a duck-typed request, and asserts
    // exactly one span was recorded. Per the otel rollout RECIPE
    // smoke-test pattern.
    const observability_enabled_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/observability_enabled_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
                .{ .name = "build_options", .module = build_options_mod },
            },
        }),
    });
    if (with_otel) {
        if (b.lazyDependency("otel", .{
            .target = target,
            .optimize = optimize,
            .otel_use_devnw_tls = otel_use_devnw_tls,
            .otel_disabled = otel_disabled,
            .otel_profiles = otel_profiles,
            .otel_use_devnw_grpc = otel_use_devnw_grpc,
        })) |otel_dep| {
            observability_enabled_tests.root_module.addImport("otel", otel_dep.module("otel"));
        }
    }
    const run_observability_enabled_tests = b.addRunArtifact(observability_enabled_tests);
    test_step.dependOn(&run_observability_enabled_tests.step);

    // Benchmark executable
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench_main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
            },
        }),
    });

    b.installArtifact(bench_exe);

    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);

    // Scale benchmark executable (JSON output for regression tracking)
    const scale_bench_exe = b.addExecutable(.{
        .name = "scale-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/scale_bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "slogz", .module = slogz_mod },
            },
        }),
    });

    b.installArtifact(scale_bench_exe);

    const run_scale_bench = b.addRunArtifact(scale_bench_exe);
    if (b.args) |args| {
        run_scale_bench.addArgs(args);
    }
    const scale_bench_step = b.step("scale-bench", "Run incremental scale benchmarks (JSON output)");
    scale_bench_step.dependOn(&run_scale_bench.step);

    // Compare benchmark executable (regression detection)
    const compare_bench_exe = b.addExecutable(.{
        .name = "compare-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/compare.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });

    b.installArtifact(compare_bench_exe);

    const run_compare_bench = b.addRunArtifact(compare_bench_exe);
    if (b.args) |args| {
        run_compare_bench.addArgs(args);
    }
    const compare_bench_step = b.step("compare-bench", "Compare benchmark results for regressions");
    compare_bench_step.dependOn(&run_compare_bench.step);

    // Compare-bench self-tests (PERF-043: gate must not silently re-break)
    const compare_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/compare.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_compare_tests = b.addRunArtifact(compare_tests);
    test_step.dependOn(&run_compare_tests.step);

    // Format step
    const fmt_step = b.step("fmt", "Format source code");
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "tests", "bench", "build.zig" },
    });
    fmt_step.dependOn(&fmt.step);

    // Check step
    const check_step = b.step("check", "Check for compilation errors");
    check_step.dependOn(&unit_tests.step);

    // Docs step
    const docs_step = b.step("docs", "Generate documentation");
    const docs_lib = b.addObject(.{
        .name = "slogz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/slogz.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    if (json_mod) |m| docs_lib.root_module.addImport("json", m);
    if (tp_mod) |sm| {
        docs_lib.root_module.addImport("thread_pool", sm);
    }
    // docs_lib creates its own module pointing at src/slogz.zig, which
    // re-exports observability + observability_init - both reach
    // @import("build_options"). Share the single instance.
    docs_lib.root_module.addImport("build_options", build_options_mod);
    if (with_otel) {
        if (b.lazyDependency("otel", .{
            .target = target,
            .optimize = optimize,
            .otel_use_devnw_tls = otel_use_devnw_tls,
            .otel_disabled = otel_disabled,
            .otel_profiles = otel_profiles,
            .otel_use_devnw_grpc = otel_use_devnw_grpc,
        })) |otel_dep| {
            docs_lib.root_module.addImport("otel", otel_dep.module("otel"));
        }
    }
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    // Examples: compile-checked so API drift is caught in CI (Q-48).
    const examples_step = b.step("examples", "Build all examples");
    const example_names = [_][]const u8{
        "basic_text",       "json_logging",   "file_rotation", "async_logging",
        "secret_redaction", "metrics_export", "i18n_logging",  "tcp_sink",
    };
    inline for (example_names) |name| {
        const example_exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/" ++ name ++ ".zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "slogz", .module = slogz_mod },
                },
            }),
        });
        examples_step.dependOn(&example_exe.step);
    }
    check_step.dependOn(examples_step);
}
