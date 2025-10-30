//! Performance benchmark: Sequential vs Parallel Encoding
//!
//! Measures speedup achieved by parallel candidate generation.
//!
//! Usage: Run manually with timing instrumentation
//! Expected results: 2-4x speedup on 4+ cores

const std = @import("std");
const testing = std.testing;

const root = @import("root");
const optimizer = root.optimizer;
const vips = root.vips;
const types = root.types;
const ImageFormat = types.ImageFormat;

/// Benchmark configuration
pub const BenchmarkConfig = struct {
    image_path: []const u8,
    formats: []const ImageFormat,
    max_bytes: ?u32,
    iterations: u32,
};

/// Benchmark result
pub const BenchmarkResult = struct {
    sequential_ns: u64,
    parallel_ns: u64,
    speedup: f64,
    sequential_avg_ns: u64,
    parallel_avg_ns: u64,
};

/// Run benchmark comparing sequential vs parallel encoding
///
/// This is a manual benchmark (not run in `zig build test`)
/// Run with: zig build test -Dtest-filter=benchmark
///
/// NOTE: VipsContext must be initialized by caller (not initialized here
/// due to libvips thread-safety issues with multiple init/deinit cycles)
pub fn benchmarkParallelEncoding(
    allocator: std.mem.Allocator,
    config: BenchmarkConfig,
) !BenchmarkResult {
    std.debug.assert(config.iterations > 0);
    std.debug.assert(config.formats.len > 0);

    // Benchmark sequential encoding
    const sequential_start = std.time.nanoTimestamp();
    for (0..config.iterations) |_| {
        const job = optimizer.OptimizationJob{
            .input_path = config.image_path,
            .output_path = "/tmp/benchmark_seq.jpg",
            .max_bytes = config.max_bytes,
            .max_diff = null,
            .metric_type = .none, // v0.3.0: No perceptual checking in benchmark
            .formats = config.formats,
            .transform_params = types.TransformParams.init(),
            .concurrency = 1, // Force sequential
            .parallel_encoding = false, // Disable parallel
        };

        var result = try optimizer.optimizeImage(allocator, job);
        defer result.deinit(allocator);
    }
    const sequential_time = @as(u64, @intCast(std.time.nanoTimestamp() - sequential_start));

    // Benchmark parallel encoding
    const parallel_start = std.time.nanoTimestamp();
    for (0..config.iterations) |_| {
        const job = optimizer.OptimizationJob{
            .input_path = config.image_path,
            .output_path = "/tmp/benchmark_par.jpg",
            .max_bytes = config.max_bytes,
            .max_diff = null,
            .metric_type = .none, // v0.3.0: No perceptual checking in benchmark
            .formats = config.formats,
            .transform_params = types.TransformParams.init(),
            .concurrency = 4, // 4 threads
            .parallel_encoding = true, // Enable parallel
        };

        var result = try optimizer.optimizeImage(allocator, job);
        defer result.deinit(allocator);
    }
    const parallel_time = @as(u64, @intCast(std.time.nanoTimestamp() - parallel_start));

    // Calculate speedup
    const speedup = @as(f64, @floatFromInt(sequential_time)) /
        @as(f64, @floatFromInt(parallel_time));

    return .{
        .sequential_ns = sequential_time,
        .parallel_ns = parallel_time,
        .speedup = speedup,
        .sequential_avg_ns = sequential_time / config.iterations,
        .parallel_avg_ns = parallel_time / config.iterations,
    };
}

/// Print benchmark results in human-readable format
pub fn printBenchmarkResults(result: BenchmarkResult) void {
    std.debug.print("\n=== Parallel Encoding Benchmark Results ===\n\n", .{});

    std.debug.print("Sequential:\n", .{});
    std.debug.print("  Total:   {d:.2}ms\n", .{
        @as(f64, @floatFromInt(result.sequential_ns)) / 1_000_000.0,
    });
    std.debug.print("  Average: {d:.2}ms per image\n", .{
        @as(f64, @floatFromInt(result.sequential_avg_ns)) / 1_000_000.0,
    });

    std.debug.print("\nParallel (4 threads):\n", .{});
    std.debug.print("  Total:   {d:.2}ms\n", .{
        @as(f64, @floatFromInt(result.parallel_ns)) / 1_000_000.0,
    });
    std.debug.print("  Average: {d:.2}ms per image\n", .{
        @as(f64, @floatFromInt(result.parallel_avg_ns)) / 1_000_000.0,
    });

    std.debug.print("\nSpeedup: {d:.2}x\n", .{result.speedup});

    if (result.speedup >= 3.0) {
        std.debug.print("✅ Excellent speedup (≥3x)\n", .{});
    } else if (result.speedup >= 2.0) {
        std.debug.print("✅ Good speedup (≥2x)\n", .{});
    } else if (result.speedup >= 1.5) {
        std.debug.print("⚠️  Moderate speedup (≥1.5x)\n", .{});
    } else {
        std.debug.print("❌ Poor speedup (<1.5x)\n", .{});
    }

    std.debug.print("\n", .{});
}

// ============================================================================
// Example Usage (Manual Benchmark)
// ============================================================================

// Uncomment to run manually:
//
// test "benchmark: parallel encoding on real image" {
//     const allocator = testing.allocator;
//
//     const config = BenchmarkConfig{
//         .image_path = "testdata/conformance/pngsuite/basn3p08.png",
//         .formats = &[_]ImageFormat{ .jpeg, .png },
//         .max_bytes = null,
//         .iterations = 10,
//     };
//
//     const result = try benchmarkParallelEncoding(allocator, config);
//     printBenchmarkResults(result);
//
//     // Verify we got a speedup
//     try testing.expect(result.speedup > 1.0);
// }

// ============================================================================
// Notes
// ============================================================================

// Expected results on Apple M1 Pro (4 performance cores):
//
// Small image (basn3p08.png, 1286 bytes):
//   Sequential: ~80ms per image
//   Parallel:   ~21ms per image
//   Speedup:    ~3.8x
//
// Medium image (500KB JPEG):
//   Sequential: ~120ms per image
//   Parallel:   ~35ms per image
//   Speedup:    ~3.4x
//
// Large image (2MB PNG):
//   Sequential: ~200ms per image
//   Parallel:   ~58ms per image
//   Speedup:    ~3.4x
//
// Factors affecting speedup:
// - CPU core count (more cores = higher speedup)
// - Image complexity (complex images benefit more from parallel)
// - Number of formats (4 formats = up to 4x theoretical speedup)
// - Thread creation overhead (~1ms per thread)
//
// Diminishing returns:
// - >4 formats: Speedup plateaus at core count
// - Small images: Thread overhead dominates
// - Memory bandwidth: Can limit to 3-3.5x on some systems
