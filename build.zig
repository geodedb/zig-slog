// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Feature flags
    const feature_journald = b.option(bool, "feature_journald", "Enable journald support (requires libsystemd)") orelse false;
    const feature_windows_eventlog = b.option(bool, "feature_windows_eventlog", "Enable Windows Event Log support") orelse false;

    // Spice parallelism option
    const enable_spice = b.option(bool, "spice", "Enable spice-based parallelism") orelse true;

    const build_options = b.addOptions();
    build_options.addOption(bool, "feature_journald", feature_journald);
    build_options.addOption(bool, "feature_windows_eventlog", feature_windows_eventlog);
    build_options.addOption(bool, "enable_spice", enable_spice);

    // Get spice dependency if enabled
    const spice_mod: ?*std.Build.Module = if (enable_spice) blk: {
        const spice_dep = b.dependency("spice", .{
            .target = target,
            .optimize = optimize,
        });
        break :blk spice_dep.module("spice");
    } else null;

    // Get dependencies
    const json_dep = b.dependency("json", .{
        .target = target,
        .optimize = optimize,
        .spice = false,
    });
    const json_mod = json_dep.module("json");

    // Main module (parallel.zig is part of the slogz module via relative import)
    const slogz_mod = b.addModule("slogz", .{
        .root_source_file = b.path("src/slogz.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "json", .module = json_mod },
        },
    });
    slogz_mod.addOptions("build_options", build_options);
    if (spice_mod) |sm| {
        slogz_mod.addImport("spice", sm);
    }

    // Link libsystemd if journald is enabled
    if (feature_journald) {
        slogz_mod.linkSystemLibrary("systemd", .{});
    }

    // Unit tests (source tests)
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/slogz.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "json", .module = json_mod },
            },
        }),
    });
    unit_tests.root_module.addOptions("build_options", build_options);
    if (spice_mod) |sm| {
        unit_tests.root_module.addImport("spice", sm);
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
    accept_tests.root_module.addOptions("build_options", build_options);
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
            .imports = &.{
                .{ .name = "json", .module = json_mod },
            },
        }),
    });
    docs_lib.root_module.addOptions("build_options", build_options);
    if (spice_mod) |sm| {
        docs_lib.root_module.addImport("spice", sm);
    }
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
