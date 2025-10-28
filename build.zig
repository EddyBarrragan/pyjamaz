const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable (optional - remove if building a library)
    const exe = b.addExecutable(.{
        .name = "your-project",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Run step (for `zig build run`)
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .name = "unit-tests",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Benchmarks (optional - uncomment if needed)
    // const benchmark = b.addExecutable(.{
    //     .name = "benchmark",
    //     .root_source_file = b.path("src/test/benchmark/main.zig"),
    //     .target = target,
    //     .optimize = .ReleaseFast,
    // });
    //
    // const run_benchmark = b.addRunArtifact(benchmark);
    // const benchmark_step = b.step("benchmark", "Run performance benchmarks");
    // benchmark_step.dependOn(&run_benchmark.step);

    // Conformance tests (optional - uncomment if needed)
    // Tests against external test suites in testdata/
    // const conformance = b.addExecutable(.{
    //     .name = "conformance-runner",
    //     .root_source_file = b.path("src/test/conformance_runner.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    //
    // const run_conformance = b.addRunArtifact(conformance);
    // run_conformance.setCwd(b.path(".")); // Run from project root
    // const conformance_step = b.step("conformance", "Run conformance tests");
    // conformance_step.dependOn(&run_conformance.step);
}
